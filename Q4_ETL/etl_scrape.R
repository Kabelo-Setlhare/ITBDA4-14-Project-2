# =====================================================================
# Question 4.1 / 4.2 - Extract + Transform  (web scraping, regex, cleaning, imputation)
# Use case: "Online-bookshop price analytics" - which categories/ratings drive price and
# stock levels?  Source: https://books.toscrape.com  (a sandbox site built for scraping practice)
#
#   live :  Rscript etl_scrape.R
#   test :  Rscript etl_scrape.R --local fixture/pages        (offline synthetic copy)
# =====================================================================
suppressPackageStartupMessages({ library(httr); library(rvest); library(xml2)
  library(dplyr); library(stringr); library(tidyr); library(ggplot2) })
dir.create("output", showWarnings = FALSE)
args      <- commandArgs(trailingOnly = TRUE)
LOCAL_DIR <- if (length(args) >= 2 && args[1] == "--local") args[2] else NULL
BASE      <- "https://books.toscrape.com/catalogue/"
N_PAGES   <- 5                                   # 5 listing pages x 20 books = 100 records (>= 20 required)
UA        <- "EduvosStudentProject/1.0 (academic use)"

get_html <- function(rel) {                      # live (polite) or local
  if (!is.null(LOCAL_DIR)) return(read_html(file.path(LOCAL_DIR, basename(rel)), encoding = "UTF-8"))
  Sys.sleep(1)                                   # 1 request / second
  r <- httr::GET(paste0(BASE, rel), httr::user_agent(UA), httr::timeout(30)); httr::stop_for_status(r)
  # NB: the server omits a charset, so we deliberately keep the raw decoding -> yields the "Â£" glitch
  read_html(httr::content(r, "text", encoding = "ISO-8859-1"))
}

# ---------------------------- 4.1  EXTRACT --------------------------------------
rating_map <- c(One = 1, Two = 2, Three = 3, Four = 4, Five = 5)
scrape_listing <- function(p) {
  pg   <- get_html(if (is.null(LOCAL_DIR)) sprintf("page-%d.html", p) else sprintf("page-%d.html", p))
  pods <- html_elements(pg, "article.product_pod")
  tibble(
    title_shown  = html_text(html_element(pods, "h3 a")),                     # often truncated with "..."
    title_attr   = html_attr(html_element(pods, "h3 a"), "title"),
    href         = html_attr(html_element(pods, "h3 a"), "href"),
    price_raw    = html_text(html_element(pods, "p.price_color")),            # e.g. "Â£51.77"
    rating_raw   = html_attr(html_element(pods, "p.star-rating"), "class"),   # "star-rating Three"
    avail_raw    = html_text(html_element(pods, "p.availability"))            # padded text
  )
}
scrape_detail <- function(href) {
  pg  <- get_html(href)
  tab <- html_elements(pg, "table.table-striped tr")
  kv  <- setNames(html_text(html_element(tab, "td")), html_text(html_element(tab, "th")))
  desc <- html_text(html_element(pg, "#product_description ~ p"))
  tibble(category = html_text(html_elements(pg, "ul.breadcrumb li a")[3]),
         upc = unname(kv["UPC"]), stock_raw = unname(kv["Availability"]),
         description = desc)
}

listing <- bind_rows(lapply(seq_len(N_PAGES), scrape_listing))
detail  <- bind_rows(lapply(listing$href, scrape_detail))
raw     <- bind_cols(listing, detail)
write.csv(raw, "output/books_raw.csv", row.names = FALSE)
cat("RAW records scraped:", nrow(raw), "\n")
cat("Raw defects found: price strings with encoding glitch =", sum(str_detect(raw$price_raw, "Â")),
    "| truncated titles =", sum(str_detect(raw$title_shown, "\\.\\.\\.$")),
    "| missing descriptions =", sum(is.na(raw$description)),
    "| duplicate UPCs =", sum(duplicated(raw$upc)), "\n")

# ---------------------------- 4.2  TRANSFORM ------------------------------------
clean <- raw %>%
  mutate(
    # regex: numerical attributes -----------------------------------------------
    price_gbp = as.numeric(str_extract(price_raw, "[0-9]+\\.[0-9]{2}")),                 # drops "Â£"
    rating    = unname(rating_map[str_extract(rating_raw, "One|Two|Three|Four|Five")]),  # word -> 1..5
    in_stock  = as.integer(str_extract(stock_raw, "(?<=\\()[0-9]+(?= available\\))")),   # "(22 available)"
    # text clean-up -------------------------------------------------------------
    title     = str_squish(title_attr),                                                   # full title from attribute
    category  = ifelse(str_to_title(str_squish(category)) %in% c("Default", "Add A Comment"), NA, str_to_title(str_squish(category))),   # site placeholders = missing                                       # "TRAVEL" -> "Travel"
    description = description %>% str_replace_all("[^[:print:]]", " ") %>%
                  str_replace_all("<[^>]+>|&[a-z]+;", " ") %>% str_squish(),
    desc_words = str_count(description, "\\b\\w+\\b")                                     # inferred numeric attribute
  ) %>%
  select(upc, title, category, price_gbp, rating, in_stock, desc_words, description) %>%
  distinct(upc, .keep_all = TRUE)                                                         # remove duplicates

cat("\nMissing values BEFORE imputation:\n"); print(colSums(is.na(clean)))

# missing-value imputation: numeric -> median of the same rating group (fallback: overall median);
#                           text    -> explicit marker + flag column
clean <- clean %>% mutate(category = ifelse(is.na(category), "Unknown", category)) %>%
  group_by(rating) %>%
  mutate(across(c(price_gbp, in_stock, desc_words),
                ~ ifelse(is.na(.x), round(median(.x, na.rm = TRUE)), .x))) %>% ungroup() %>%
  mutate(across(c(price_gbp, in_stock, desc_words), ~ ifelse(is.na(.x), round(median(.x, na.rm = TRUE), 2), .x)),
         description_missing = is.na(description) | description == "",
         description = ifelse(description_missing, "No description available", description))

# outlier check (IQR rule) - flagged, not deleted
q <- quantile(clean$price_gbp, c(.25, .75)); iqr <- diff(q)
clean$price_outlier <- clean$price_gbp < q[1] - 1.5 * iqr | clean$price_gbp > q[2] + 1.5 * iqr

cat("\nMissing values AFTER imputation:\n"); print(colSums(is.na(clean)))
write.csv(clean, "output/books_clean.csv", row.names = FALSE, fileEncoding = "UTF-8")
cat("\nCLEAN records:", nrow(clean), "-> output/books_clean.csv\n"); print(head(clean %>% select(-description), 8))

ggplot(clean, aes(category, price_gbp, fill = category)) + geom_boxplot(show.legend = FALSE) +
  labs(title = "Book price by category (cleaned data)", x = "Category", y = "Price (GBP)") + theme_minimal()
ggsave("output/fig_price_by_category.png", width = 8, height = 5, dpi = 150)
