-- Investigation 1: Does a higher rating mean a higher price?  (aggregation by rating)
SELECT rating,
       COUNT(*)                          AS n_books,
       ROUND(AVG(price_gbp), 2)          AS avg_price,
       ROUND(MIN(price_gbp), 2)          AS min_price,
       ROUND(MAX(price_gbp), 2)          AS max_price,
       ROUND(AVG(in_stock), 1)           AS avg_stock
FROM   books
GROUP  BY rating
ORDER  BY rating;

-- Investigation 2: Where is stock value concentrated?  (category level + window function ranking)
WITH cat AS (
    SELECT category,
           COUNT(*)                           AS n_books,
           ROUND(AVG(price_gbp), 2)           AS avg_price,
           SUM(price_gbp * in_stock)::NUMERIC(10,2) AS stock_value
    FROM   books
    GROUP  BY category
)
SELECT category, n_books, avg_price, stock_value,
       ROUND(100 * stock_value / SUM(stock_value) OVER (), 1) AS pct_of_total_value,
       RANK() OVER (ORDER BY stock_value DESC)               AS value_rank
FROM   cat
ORDER  BY value_rank;

-- Bonus: most expensive title in each category (DISTINCT ON)
SELECT DISTINCT ON (category) category, title, price_gbp, rating
FROM   books
ORDER  BY category, price_gbp DESC;
