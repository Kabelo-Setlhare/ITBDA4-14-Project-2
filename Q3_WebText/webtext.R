# =====================================================================
# Question 3 - WebText API proof of concept
#   3.1  Responsible web scraping  -> R data structure
#   3.2  Text pre-processing
#   3.3  Summarisation (frequency-based + TextRank) with visualisations
#
# =====================================================================
suppressPackageStartupMessages({
  library(httr); library(rvest); library(xml2)
  library(dplyr); library(tidyr); library(stringr); library(tidytext)
  library(SnowballC); library(igraph); library(ggplot2); library(wordcloud)
})
dir.create("output", showWarnings = FALSE)

args <- commandArgs(trailingOnly = TRUE)
DEFAULT_URL <- "https://en.wikipedia.org/wiki/Natural_language_processing"
USER_AGENT  <- "EduvosStudentProject/1.0 (academic use; contact: student@example.com)"
N_SENT      <- 5      # sentences in each summary

# ---------------------------------------------------------------------
# 3.1  Extraction ("fair use of web-scraping")
#      - single page, no crawling       - identify ourselves with a User-Agent
#      - honour robots.txt              - rate limit / timeout
#      - Wikipedia text is CC BY-SA: keep the source URL and attribute it
# ---------------------------------------------------------------------
allowed_by_robots <- function(url, agent = "*") {
  u  <- httr::parse_url(url)
  rb <- tryCatch(httr::GET(paste0(u$scheme, "://", u$hostname, "/robots.txt"),
                           httr::user_agent(USER_AGENT), httr::timeout(15)),
                 error = function(e) NULL)
  if (is.null(rb) || httr::status_code(rb) != 200) return(TRUE)  # no robots.txt -> allowed
  lines <- strsplit(httr::content(rb, "text", encoding = "UTF-8"), "\r?\n")[[1]]
  applies <- FALSE; disallow <- character()
  for (l in lines) {
    l <- trimws(sub("#.*$", "", l))
    if (grepl("^user-agent:", l, ignore.case = TRUE))
      applies <- trimws(sub("^user-agent:", "", l, ignore.case = TRUE)) %in% c(agent, "*")
    else if (applies && grepl("^disallow:", l, ignore.case = TRUE)) {
      p <- trimws(sub("^disallow:", "", l, ignore.case = TRUE))
      if (nzchar(p)) disallow <- c(disallow, p)
    }
  }
  path <- if (is.null(u$path)) "/" else paste0("/", u$path)
  !any(startsWith(path, disallow))
}

scrape_page <- function(source, is_file = FALSE) {
  if (is_file) {
    page <- read_html(source, encoding = "UTF-8"); url <- paste0("file://", normalizePath(source))
  } else {
    stopifnot(allowed_by_robots(source))
    Sys.sleep(1)                                     # polite delay
    resp <- httr::GET(source, httr::user_agent(USER_AGENT), httr::timeout(30))
    httr::stop_for_status(resp)
    page <- read_html(httr::content(resp, "text", encoding = "UTF-8")); url <- source
  }
  # remove everything that is not article content
  xml_remove(xml_find_all(page, "//script|//style|//noscript|//nav|//header|//footer|//aside|//form|//figure|//table|//sup[contains(@class,'reference')]|//*[contains(@class,'navbox') or contains(@class,'mw-editsection') or contains(@class,'infobox')]"))
  title <- html_text2(html_element(page, "h1")); if (is.na(title)) title <- html_text2(html_element(page, "title"))
  paras <- html_text2(html_elements(page, "main p, article p, #mw-content-text p, body p"))
  paras <- unique(paras)
  tibble(url = url, title = title, retrieved = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
         para_id = seq_along(paras), raw_text = paras)
}

# ---------------------------------------------------------------------
# 3.2  Pre-processing
# ---------------------------------------------------------------------
clean_paragraph <- function(x) {
  x %>% iconv(to = "UTF-8", sub = " ") %>%
    str_replace_all("\\[[0-9a-z ]{1,12}\\]", " ") %>%        # citation marks [1] [citation needed]
    str_replace_all("\\[citation needed\\]", " ") %>%
    str_replace_all("https?://\\S+|www\\.\\S+", " ") %>%      # URLs
    str_replace_all("\\S+@\\S+\\.\\S+", " ") %>%              # e-mail addresses
    str_replace_all("[\u2018\u2019]", "'") %>% str_replace_all("[\u201C\u201D]", "\"") %>%
    str_replace_all("[\u00A0\u200B]", " ") %>%                # non-breaking / zero-width spaces
    str_squish()
}
BOILERPLATE <- "(?i)(share this|subscribe|all rights reserved|copyright|click here|follow us|related articles|cookie)"

preprocess <- function(raw) {
  raw %>%
    mutate(text = clean_paragraph(raw_text)) %>%
    filter(nchar(text) >= 40, !str_detect(text, BOILERPLATE)) %>%      # drop menus, footers, captions
    distinct(text, .keep_all = TRUE)
}

sentence_table <- function(clean) {
  clean %>% unnest_tokens(sentence, text, token = "sentences", to_lower = FALSE) %>%
    filter(str_count(sentence, "\\w+") >= 5) %>%
    mutate(sent_id = row_number())
}

word_table <- function(sent) {                         # tokens, stop-words, numbers removed, stemmed
  sent %>% unnest_tokens(word, sentence, token = "words", drop = FALSE) %>%
    filter(!word %in% stop_words$word, !str_detect(word, "[0-9]"), nchar(word) > 2) %>%
    mutate(stem = wordStem(word, language = "english"))
}

# ---------------------------------------------------------------------
# 3.3  Summarisation
# ---------------------------------------------------------------------
# (A) Frequency-based extractive summary: sentence score = mean normalised stem frequency
freq_summary <- function(sent, words, n = N_SENT) {
  freq <- words %>% count(stem, sort = TRUE) %>% mutate(w = n / max(n))
  scores <- words %>% left_join(freq %>% select(stem, w), by = "stem") %>%
    group_by(sent_id) %>% summarise(score = sum(w) / n(), .groups = "drop")
  sent %>% left_join(scores, by = "sent_id") %>% mutate(score = replace_na(score, 0)) %>%
    mutate(selected = rank(-score, ties.method = "first") <= n)
}

# (B) TextRank: PageRank on a sentence-similarity graph built from TF-IDF cosine similarity
textrank_summary <- function(sent, words, n = N_SENT, threshold = 0.05) {
  tfidf <- words %>% count(sent_id, stem) %>% bind_tf_idf(stem, sent_id, n)
  m <- tfidf %>% select(sent_id, stem, tf_idf) %>% pivot_wider(names_from = stem, values_from = tf_idf, values_fill = 0)
  ids <- m$sent_id; mat <- as.matrix(m[, -1]); nrm <- sqrt(rowSums(mat^2)); nrm[nrm == 0] <- 1
  sim <- (mat / nrm) %*% t(mat / nrm); diag(sim) <- 0; sim[sim < threshold] <- 0
  dimnames(sim) <- list(ids, ids)
  g  <- graph_from_adjacency_matrix(sim, mode = "undirected", weighted = TRUE)
  pr <- page_rank(g)$vector
  out <- sent %>% mutate(rank_score = pr[as.character(sent_id)]) %>%
    mutate(rank_score = replace_na(rank_score, 0), selected = rank(-rank_score, ties.method = "first") <= n)
  list(table = out, graph = g)
}

# ---------------------------------------------------------------------
# Main pipeline 
# ---------------------------------------------------------------------
webtext_api <- function(source, is_file = FALSE) {
  raw   <- scrape_page(source, is_file)                       # 3.1
  clean <- preprocess(raw)                                    # 3.2
  sent  <- sentence_table(clean); words <- word_table(sent)
  fs    <- freq_summary(sent, words)                          # 3.3 (A)
  tr    <- textrank_summary(sent, words)                      # 3.3 (B)
  list(raw = raw, clean = clean, sentences = sent, words = words,
       freq_summary = fs, textrank = tr$table, graph = tr$graph)
}

if (sys.nframe() == 0) {
  is_file <- length(args) >= 2 && args[1] == "--file"
  source  <- if (is_file) args[2] else if (length(args) == 1) args[1] else DEFAULT_URL
  res <- webtext_api(source, is_file)

  cat("\n=== 3.1 Extracted R data structure ===\n"); print(res$raw %>% mutate(raw_text = str_trunc(raw_text, 70)))
  cat("\nPage title:", res$raw$title[1], "\nParagraphs extracted:", nrow(res$raw), "\n")
  cat("\n=== 3.2 After pre-processing ===\nParagraphs kept:", nrow(res$clean),
      "| sentences:", nrow(res$sentences), "| content tokens:", nrow(res$words),
      "| unique stems:", n_distinct(res$words$stem), "\n")
  saveRDS(res, "output/webtext_result.rds")
  write.csv(res$clean, "output/clean_paragraphs.csv", row.names = FALSE)

  top_sent <- function(df, col) df %>% filter(selected) %>% arrange(sent_id) %>% pull(sentence)
  cat("\n=== 3.3(A) Frequency-based summary ===\n"); cat(paste0("- ", top_sent(res$freq_summary)), sep = "\n")
  cat("\n=== 3.3(B) TextRank summary ===\n");        cat(paste0("- ", top_sent(res$textrank)), sep = "\n")
  overlap <- length(intersect(res$freq_summary$sent_id[res$freq_summary$selected],
                              res$textrank$sent_id[res$textrank$selected]))
  cat("\nSentences chosen by BOTH methods:", overlap, "of", N_SENT, "\n")
  writeLines(c("FREQUENCY SUMMARY", paste0("- ", top_sent(res$freq_summary)), "",
               "TEXTRANK SUMMARY",  paste0("- ", top_sent(res$textrank))), "output/summaries.txt")

  # ---- visualisations --------------------------------------------------
  top_words <- res$words %>% group_by(stem) %>%
    summarise(word = names(sort(table(word), decreasing = TRUE))[1], n = n(), .groups = "drop") %>%
    slice_max(n, n = 15, with_ties = FALSE)
  p1 <- ggplot(top_words, aes(n, reorder(word, n))) + geom_col(fill = "steelblue") +
    labs(title = "Fig 1: 15 most frequent content words", subtitle = res$raw$title[1],
         x = "Frequency (stop-words removed, stems merged)", y = NULL) + theme_minimal()
  ggsave("output/fig1_top_words.png", p1, width = 7, height = 5, dpi = 150)

  png("output/fig2_wordcloud.png", width = 900, height = 700, res = 130)
  wc <- res$words %>% count(word, sort = TRUE) %>% slice_head(n = 60)
  wordcloud(wc$word, wc$n, min.freq = 1, random.order = FALSE, colors = RColorBrewer::brewer.pal(8, "Dark2"))
  title("Fig 2: Word cloud of the page content"); dev.off()

  cmp <- bind_rows(
    res$freq_summary %>% transmute(sent_id, score = score / max(score), method = "Frequency score", selected),
    res$textrank     %>% transmute(sent_id, score = rank_score / max(rank_score), method = "TextRank score", selected))
  p3 <- ggplot(cmp, aes(sent_id, score, fill = selected)) + geom_col() + facet_wrap(~ method, ncol = 1) +
    scale_fill_manual(values = c(`FALSE` = "grey75", `TRUE` = "firebrick"), labels = c("not chosen", "in summary")) +
    labs(title = "Fig 3: Sentence importance by summarisation method",
         x = "Sentence position in the document", y = "Normalised score", fill = NULL) + theme_minimal()
  ggsave("output/fig3_sentence_scores.png", p3, width = 8, height = 6, dpi = 150)

  g <- res$graph; sel <- res$textrank$selected[match(as.integer(V(g)$name), res$textrank$sent_id)]
  V(g)$color <- ifelse(sel, "firebrick", "lightblue")
  V(g)$size  <- 6 + 60 * page_rank(g)$vector
  png("output/fig4_textrank_graph.png", width = 1000, height = 800, res = 130)
  set.seed(1); plot(g, layout = layout_with_fr(g), vertex.label = V(g)$name, vertex.label.cex = 0.6,
                    edge.width = 4 * E(g)$weight, main = "Fig 4: TextRank sentence-similarity graph\n(red = selected, size = PageRank)")
  dev.off()
  cat("\nFigures and tables saved to ./output\n")
}
