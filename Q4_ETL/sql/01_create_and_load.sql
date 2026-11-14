-- Q4.3  Load the cleaned CSV into PostgreSQL
-- run:  psql -d bookstore -f sql/01_create_and_load.sql      (from the Q4_ETL folder)
DROP TABLE IF EXISTS books;
CREATE TABLE books (
    upc                 VARCHAR(20) PRIMARY KEY,
    title               TEXT        NOT NULL,
    category            VARCHAR(50) NOT NULL,
    price_gbp           NUMERIC(6,2) NOT NULL CHECK (price_gbp >= 0),
    rating              SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
    in_stock            INTEGER     NOT NULL CHECK (in_stock >= 0),
    desc_words          NUMERIC(7,2),
    description         TEXT,
    description_missing BOOLEAN,
    price_outlier       BOOLEAN
);
\copy books FROM 'output/books_clean.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
SELECT COUNT(*) AS rows_loaded FROM books;
