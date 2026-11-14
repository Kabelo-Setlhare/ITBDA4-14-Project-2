# ITBDA4 Practice Project - Big Data Analytics

| Folder | Question | Language |
|---|---|---|
| `Q1_MapReduce/` | Q1 Hadoop MapReduce keyword (row, column) search | Java (Hadoop 3.x) |
| `Q2_LDA/` | Q2 LDA topic modelling of `news.zip` | R |
| `Q3_WebText/` | Q3 WebText API: scrape, pre-process, summarise | R |
| `Q4_ETL/` | Q4 scrape -> clean -> CSV -> PostgreSQL -> SQL analysis | R + SQL |
| `notebooks/` | R Markdown notebooks showing the analytics flow (Q1-Q4) | Rmd |
| `docs/PROJECT_REPORT.md` | Written answers / documentation for all questions | Markdown |

## What has been executed and what you still need to run

| Part | Status |
|---|---|
| Q1 | Compiled and **run** in Hadoop local mode (Hadoop 3.3.4 client libraries, OpenJDK 21). Output cross-checked against an independent Python implementation (identical). `pom.xml`, the `conf/*.xml` files and the HDFS/YARN script were **not** run (no Maven Central or cluster available). |
| Q2 | **Run** on the supplied `news.zip`; all tables/figures in `Q2_LDA/output/` are real results. |
| Q3 | Pipeline **run offline** on a saved HTML page (the supplied `news_8.txt` wrapped in menus/footers). **Not yet run against a live URL** - run `Rscript webtext.R <url>` on your machine and keep that output for submission. |
| Q4 | Pipeline and SQL **run offline** on a *synthetic* copy of the books.toscrape.com page structure (`Q4_ETL/fixture`). The numbers in `Q4_ETL/output/sql_results_fixture.txt` are from fake data and must not be reported. Run `Rscript etl_scrape.R` live, then the SQL, and write your interpretation from your own results. |

## Quick start
```bash
# Q1 (Hadoop + Maven installed)
cd Q1_MapReduce && scripts/build.sh && scripts/run_local.sh africa
# Q2
cd Q2_LDA && Rscript lda_news.R 3 10
# Q3 (live)
cd Q3_WebText && Rscript webtext.R "https://en.wikipedia.org/wiki/Natural_language_processing"
# Q4 (live)
cd Q4_ETL && Rscript etl_scrape.R && createdb bookstore && psql -d bookstore -f sql/01_create_and_load.sql && psql -d bookstore -f sql/02_analysis.sql
```
R packages: tm, topicmodels, tidytext, dplyr, tidyr, stringr, ggplot2, wordcloud, reshape2, rvest, httr, xml2, SnowballC, igraph, slam.

Before you submit, replace the placeholder contact e-mail in the `User-Agent` strings (Q3/Q4 scripts) with your own.
