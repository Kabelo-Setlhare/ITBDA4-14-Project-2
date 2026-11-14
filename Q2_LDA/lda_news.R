# =====================================================================
# Question 2 - Topic modelling of the news corpus with LDA
# Run from the Q2_LDA folder:  Rscript lda_news.R [n_topics] [top_k]
# =====================================================================
suppressPackageStartupMessages({
  library(tm); library(topicmodels); library(tidytext)
  library(dplyr); library(tidyr); library(stringr)
  library(ggplot2); library(wordcloud); library(reshape2)
})

args     <- commandArgs(trailingOnly = TRUE)
N_TOPICS <- if (length(args) >= 1) as.integer(args[1]) else 3   # n topics
TOP_K    <- if (length(args) >= 2) as.integer(args[2]) else 10  # k words/topic
SEED     <- 2026
dir.create("output", showWarnings = FALSE)

# ---------------------------------------------------------------------
# 2.1  Build the data frame (file_name, content) and denoise it
# ---------------------------------------------------------------------
files <- list.files("data/sa_news", pattern = "\\.txt$", full.names = TRUE)
files <- files[order(as.integer(str_extract(basename(files), "\\d+")))]

news_raw <- data.frame(
  file_name = basename(files),
  content   = vapply(files, function(f)
    paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    character(1)),
  stringsAsFactors = FALSE, row.names = NULL
)
cat("Documents loaded:", nrow(news_raw), "\n")

# Custom noise: boiler-plate that carries no topical meaning
noise_words <- c("said", "also", "will", "told", "per", "cent", "according",
                 "monday", "tuesday", "wednesday", "thursday", "friday",
                 "saturday", "sunday", "january", "february", "march", "april",
                 "may", "june", "july", "august", "september", "october",
                 "november", "december", "year", "years", "last", "new")

clean_text <- function(x) {
  x <- iconv(x, to = "UTF-8", sub = " ")
  x <- str_replace_all(x, "[\u2018\u2019\u201C\u201D]", "'")   # curly quotes
  x <- str_replace_all(x, "(?i)[-\u2013\u2014]?\\s*SAnews\\.gov\\.za", " ")  # source sign-off
  x <- str_replace_all(x, "https?://\\S+|www\\.\\S+", " ")     # URLs
  x <- str_replace_all(x, "\\S+@\\S+", " ")                    # e-mails
  x <- str_replace_all(x, "<[^>]+>", " ")                      # html tags
  x <- str_replace_all(x, "&[a-z]+;", " ")                     # html entities
  x <- tolower(x)
  x <- str_replace_all(x, "'s\\b", "")                         # possessives
  x <- str_replace_all(x, "[[:punct:]]+", " ")                 # punctuation
  x <- str_replace_all(x, "[[:digit:]]+", " ")                 # numbers
  x <- str_replace_all(x, "\\b[a-z]{1,2}\\b", " ")             # 1-2 letter tokens
  x <- removeWords(x, c(stopwords("en"), noise_words))         # stop-words
  str_squish(x)                                                # whitespace
}

news <- news_raw %>% mutate(clean = clean_text(content))
write.csv(news, "output/news_dataframe.csv", row.names = FALSE)
cat("\n--- Before / after denoising (news_1.txt) ---\n")
cat(substr(news$content[1], 1, 250), "\n=>\n", substr(news$clean[1], 1, 250), "\n")

# Document-term matrix; drop very rare terms (appear in a single doc only)
corpus <- VCorpus(VectorSource(news$clean))
dtm    <- DocumentTermMatrix(corpus, control = list(wordLengths = c(3, Inf)))
dtm    <- dtm[, slam::col_sums(dtm > 0) >= 2]
dtm    <- dtm[slam::row_sums(dtm) > 0, ]
rownames(dtm) <- news$file_name
cat("\nDTM:", nrow(dtm), "docs x", ncol(dtm), "terms\n")

# ---------------------------------------------------------------------
# 2.2  LDA (Gibbs sampling)
# ---------------------------------------------------------------------
# Choosing n: compare candidate values by perplexity on a held-out split
set.seed(SEED)
train_id <- sample(seq_len(nrow(dtm)), size = ceiling(0.7 * nrow(dtm)))
cand <- 2:6
perp <- sapply(cand, function(k) {
  m <- LDA(dtm[train_id, ], k = k, method = "Gibbs",
           control = list(seed = SEED, burnin = 500, iter = 1000))
  perplexity(m, newdata = dtm[-train_id, ])
})
perp_df <- data.frame(k = cand, perplexity = perp)
print(perp_df)
write.csv(perp_df, "output/perplexity_by_k.csv", row.names = FALSE)

p_perp <- ggplot(perp_df, aes(k, perplexity)) +
  geom_line(colour = "steelblue") + geom_point(size = 3, colour = "steelblue") +
  labs(title = "Held-out perplexity vs number of topics",
       subtitle = "Lower is better; 10-document corpus so interpret with care",
       x = "Number of topics (n)", y = "Perplexity") + theme_minimal()
ggsave("output/fig0_perplexity.png", p_perp, width = 7, height = 4, dpi = 150)

# Final model on the full corpus
lda_fit <- LDA(dtm, k = N_TOPICS, method = "Gibbs",
               control = list(seed = SEED, burnin = 1000, iter = 3000, thin = 50))

# Topic-word distribution (beta) and document-topic distribution (gamma)
beta  <- tidy(lda_fit, matrix = "beta")
gamma <- tidy(lda_fit, matrix = "gamma")

top_terms <- beta %>% group_by(topic) %>%
  slice_max(beta, n = TOP_K, with_ties = FALSE) %>%
  arrange(topic, desc(beta)) %>% ungroup()

cat("\n=== Top", TOP_K, "words per topic (with P(word | topic)) ===\n")
print(as.data.frame(top_terms %>% mutate(beta = round(beta, 4))), row.names = FALSE)
cat("\n=== Compact view ===\n")
print(terms(lda_fit, TOP_K))

write.csv(top_terms, "output/top_terms_per_topic.csv", row.names = FALSE)
write.csv(gamma,     "output/doc_topic_distribution.csv", row.names = FALSE)

dominant <- gamma %>% group_by(document) %>% slice_max(gamma, n = 1) %>% ungroup()
cat("\n=== Dominant topic per document ===\n"); print(as.data.frame(dominant))
cat("\nTopic sizes (documents):\n"); print(table(dominant$topic))
write.csv(dominant, "output/dominant_topic_per_document.csv", row.names = FALSE)

# ---------------------------------------------------------------------
# 2.3  Visualisations (four methods)
# ---------------------------------------------------------------------
# (a) Faceted bar charts of word probabilities
p1 <- top_terms %>% mutate(term = reorder_within(term, beta, topic)) %>%
  ggplot(aes(beta, term, fill = factor(topic))) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~ paste("Topic", topic), scales = "free_y") +
  scale_y_discrete(labels = function(x) gsub("__.+$", "", x)) +
  labs(title = paste("Top", TOP_K, "words per topic (LDA)"),
       x = expression(beta ~ "= P(word | topic)"), y = NULL) +
  theme_minimal(base_size = 11)
ggsave("output/fig1_top_terms_bars.png", p1, width = 10, height = 6, dpi = 150)

# (b) One word cloud per topic
png("output/fig2_wordclouds.png", width = 1500, height = 550, res = 130)
par(mfrow = c(1, N_TOPICS), mar = c(0.5, 0.5, 2, 0.5))
for (t in seq_len(N_TOPICS)) {
  d <- beta %>% filter(topic == t) %>% slice_max(beta, n = 30, with_ties = FALSE)
  wordcloud(d$term, d$beta, scale = c(2.6, 0.5), min.freq = 0,
            random.order = FALSE, colors = RColorBrewer::brewer.pal(8, "Dark2"))
  title(paste("Topic", t))
}
dev.off()

# (c) Heat-map of document-topic proportions
p3 <- ggplot(gamma, aes(factor(topic), document, fill = gamma)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.2f", gamma)), size = 3) +
  scale_fill_gradient(low = "white", high = "firebrick") +
  labs(title = "Document-topic distribution (gamma)", x = "Topic",
       y = NULL, fill = "P(topic | doc)") + theme_minimal()
ggsave("output/fig3_doc_topic_heatmap.png", p3, width = 7, height = 5, dpi = 150)

# (d) Terms that best separate two topics (log2 ratio of betas)
if (N_TOPICS >= 2) {
  wide <- beta %>% mutate(topic = paste0("t", topic)) %>%
    pivot_wider(names_from = topic, values_from = beta) %>%
    filter(t1 > 0.002 | t2 > 0.002) %>% mutate(log_ratio = log2(t2 / t1))
  p4 <- bind_rows(slice_max(wide, log_ratio, n = 8), slice_min(wide, log_ratio, n = 8)) %>%
    mutate(term = reorder(term, log_ratio)) %>%
    ggplot(aes(log_ratio, term, fill = log_ratio > 0)) +
    geom_col(show.legend = FALSE) +
    labs(title = "Words that most separate Topic 2 from Topic 1",
         x = "log2(beta2 / beta1)", y = NULL) + theme_minimal()
  ggsave("output/fig4_topic1_vs_topic2.png", p4, width = 7, height = 5, dpi = 150)
}
cat("\nAll outputs written to ./output\n")
