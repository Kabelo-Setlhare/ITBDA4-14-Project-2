# ITBDA4 Practice Project - Report

## Question 1 - Hadoop MapReduce keyword search

### 1.1 Logical design
Diagram: `Q1_MapReduce/diagram/mapreduce_logical_layout.png`.

1. **Driver** receives the input folder, the output folder and the keyword (`-D search.keyword=africa` or 3rd argument). The keyword is stored in the job `Configuration`, so it is never hard-coded.
2. **Input split.** `WholeFileTextInputFormat` refuses to split files, so each document is read by exactly one mapper from its first to its last line. This is what makes a line counter a valid *row* number (plain `TextInputFormat` only provides byte offsets).
3. **Map.** For every line the mapper increments the row counter, runs a case-insensitive regex for the keyword and, for each hit, emits `(fileName, "row,column")`. Column = 1-based character position in that line. A line with several hits emits several pairs.
4. **Shuffle & sort.** The framework groups all pairs with the same file name.
5. **Reduce.** The reducer receives `(fileName, [locations])`, sorts them numerically by row then column (Hadoop does not order values inside a group), counts them and writes `fileName  count=N  (r,c) (r,c) ...`.
6. **Output** `part-r-00000`. Files with no hit produce no line.

Design choice: matching is **whole word** by default (`africa` does not match `African`). `-D search.wholeword=false` switches to substring matching.

### 1.2 - 1.4 Code
| Item | File |
|---|---|
| Mapper | `src/main/java/za/ac/eduvos/mr/KeywordLocationMapper.java` |
| Reducer | `.../KeywordLocationReducer.java` |
| Configuration / driver | `.../KeywordSearchDriver.java`, `conf/*.xml`, `pom.xml` |
| Non-splittable input format | `.../WholeFileTextInputFormat.java` |

Key configuration settings: `search.keyword`, `search.wholeword`, `mapreduce.framework.name` (local / yarn), `fs.defaultFS` (file:/// / hdfs://), `mapreduce.job.reduces=1`, speculative execution off, task timeout, memory per task, input/output formats and key/value classes.

### Demonstration evidence (keyword `africa`, `evidence/`)
Whole-word, case-insensitive:
```
doc1.txt  count=1  (1,64)
doc2.txt  count=3  (1,57) (33,24) (58,81)
doc3.txt  count=8  (1,38) (3,7) (5,7) (40,146) (46,7) (50,142) (52,86) (54,44)
doc5.txt  count=4  (1,62) (3,88) (23,121) (38,27)
```
doc4, doc6 and doc7 contain no occurrence. With `-D search.wholeword=false` the extra hits are words such as "African" (e.g. doc1 3 hits, doc3 9 hits) - see `evidence/output_substring/`. Run logs are in `evidence/*.log`. The output was verified against an independent Python re-implementation (identical for every file, row and column). Running with no keyword stops with exit code 2 and a usage message, which shows the keyword is truly dynamic.

## Question 2 - LDA on `news.zip` (real results)

**2.1** `lda_news.R` builds the `file_name, content` data frame (10 articles, `output/news_dataframe.csv`), then denoises: encoding repair, curly quotes, URLs, e-mails, HTML, possessives, punctuation, digits, 1-2 letter tokens, English stop-words, date/calendar words, and the "SAnews.gov.za" sign-off that appears in every article. Terms found in only one document were dropped (195 terms remain).

**2.2** LDA with Gibbs sampling (`topicmodels`), n = 3 topics, k = 10 words (both are command-line parameters). Held-out perplexity was compared for n = 2-6 (`output/perplexity_by_k.csv`); it keeps falling, but the hold-out set is only 3 documents, so I chose n = 3 for interpretability. Mention this limitation in your write-up.

| Topic | Top words (P(word given topic) in `output/top_terms_per_topic.csv`) | Reading |
|---|---|---|
| 1 | public, department, government, south, africa, administration, country, governments | Government and public administration |
| 2 | service, national, psc, days, gxoyiya, report, management, school, payment | Public Service Commission - late payment of supplier invoices |
| 3 | eskom, police, expected, west, african, power, communities | Eskom/police fraud and crime cases |

Dominant topic per document (`output/dominant_topic_per_document.csv`): topic 3 -> news_1, 4, 5, 10; topic 2 -> news_2, 6, 9; topic 1 -> news_3, 7, 8. The topic labels are my interpretation of the word lists; document proportions are only 0.39-0.65, which is expected for a ten-article corpus.

**2.3** Four visualisations in `Q2_LDA/output/`: faceted bar charts of word probability (fig1), word clouds per topic (fig2), document-topic heat-map (fig3), and a log-ratio chart of the words that separate topics 1 and 2 (fig4). Perplexity vs n is fig0.

## Question 3 - WebText API
`Q3_WebText/webtext.R` exposes `webtext_api(url)`: link in, insights out.
* **3.1 Extraction.** Responsible scraping: single page, robots.txt check, descriptive User-Agent, 1 s delay, source URL kept (Wikipedia text is CC BY-SA, attribute it). Non-content nodes (script, style, nav, header, footer, aside, forms, tables, reference markers) are removed; paragraphs go into a tibble (`url, title, retrieved, para_id, raw_text`).
* **3.2 Pre-processing.** Citation marks, URLs, e-mails, odd whitespace/quotes removed; short and boiler-plate paragraphs and duplicates dropped; sentence split; tokenise, stop-word and number removal, stemming.
* **3.3 Summarisation.** (A) frequency-based extractive summary; (B) TextRank (PageRank over a TF-IDF cosine-similarity graph). Four figures: top words, word cloud, sentence scores by method, TextRank graph. The two methods' overlap is printed.

The offline test on the supplied article gave 22 paragraphs -> 20 kept, 22 sentences, 191 unique stems, and both methods agreed on 2 of 5 sentences. **Re-run it on your live URL and describe *those* figures** (the marking asks for fully labelled graphs and described findings).

## Question 4 - ETL with R and PostgreSQL
* **Use case:** bookshop price/stock analytics on books.toscrape.com (a practice site that permits scraping). 2 listing pages + detail pages = 40 records.
* **4.1** `etl_scrape.R` extracts title, price string, rating class, availability text, category, UPC, description; regex converts them to numbers (`price_gbp`, `rating`, `in_stock`, `desc_words`). The raw data naturally contains the "Â£" encoding glitch, truncated titles, padded text, and records lacking a description.
* **4.2** Cleaning: encoding repair, title restored from the `title` attribute, whitespace/HTML removal, category case fixed, duplicates removed by UPC, missing numeric values imputed with the median of the same rating group, missing text flagged and marked, IQR outlier flag. Exported to `output/books_clean.csv`.
* **4.3** `sql/01_create_and_load.sql` (table with constraints + `\copy`) and `sql/02_analysis.sql`: (1) price, range and stock by rating; (2) stock value by category with a window function (share of total, rank). Interpret *your* live output: say whether price rises with rating, which category holds most stock value and whether that comes from many titles or high prices.
* **4.4** Push this folder to GitHub (documentation = `docs/`, datasets = `Q*/output`, `Q2_LDA/data`, `Q1_MapReduce/input`, notebooks = `notebooks/`).
