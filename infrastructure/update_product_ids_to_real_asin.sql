-- One-time update: replace placeholder product IDs with real Amazon ASINs
-- so that amazon_url links resolve to real product pages.
-- Run with: docker-compose exec -T postgres psql -U postgres -d ecommerce -f - < infrastructure/update_product_ids_to_real_asin.sql
-- Or from inside the container: psql -U postgres -d ecommerce -f /path/to/update_product_ids_to_real_asin.sql

UPDATE products SET product_id = 'B08F2866Q3', amazon_url = 'https://www.amazon.com/dp/B08F2866Q3' WHERE product_id = 'B08XYZ123';
UPDATE products SET product_id = 'B0D1XD1ZV3', amazon_url = 'https://www.amazon.com/dp/B0D1XD1ZV3' WHERE product_id = 'B09ABC456';
UPDATE products SET product_id = 'B09XS7JWHH', amazon_url = 'https://www.amazon.com/dp/B09XS7JWHH' WHERE product_id = 'B09GHI345';
UPDATE products SET product_id = 'B094C4VDJZ', amazon_url = 'https://www.amazon.com/dp/B094C4VDJZ' WHERE product_id = 'B095T3G1M5';
UPDATE products SET product_id = 'B09BYFHL25', amazon_url = 'https://www.amazon.com/dp/B09BYFHL25' WHERE product_id = 'B08VJT9K2K';
UPDATE products SET product_id = 'B0BDHB9Y8H', amazon_url = 'https://www.amazon.com/dp/B0BDHB9Y8H' WHERE product_id = 'B1HGL6Z4H4';
UPDATE products SET product_id = 'B098FKXT8L', amazon_url = 'https://www.amazon.com/dp/B098FKXT8L' WHERE product_id = 'B07XYZ789';
UPDATE products SET product_id = 'B08HR6ZBYJ', amazon_url = 'https://www.amazon.com/dp/B08HR6ZBYJ' WHERE product_id = 'B09EFG789';
UPDATE products SET product_id = 'B096SV8SJG', amazon_url = 'https://www.amazon.com/dp/B096SV8SJG' WHERE product_id = 'B096GT2LQ5';
UPDATE products SET product_id = 'B0B2SH56BZ', amazon_url = 'https://www.amazon.com/dp/B0B2SH56BZ' WHERE product_id = 'B0B7CPSN2P';
UPDATE products SET product_id = 'B0BS1QCFHX', amazon_url = 'https://www.amazon.com/dp/B0BS1QCFHX' WHERE product_id = 'B0BT1K1L8Q';
UPDATE products SET product_id = 'B08C1W5N87', amazon_url = 'https://www.amazon.com/dp/B08C1W5N87' WHERE product_id = 'B09KLM345';
UPDATE products SET product_id = 'B094YV1S9T', amazon_url = 'https://www.amazon.com/dp/B094YV1S9T' WHERE product_id = 'B09T44K2L7';
UPDATE products SET product_id = 'B0748G1QLP', amazon_url = 'https://www.amazon.com/dp/B0748G1QLP' WHERE product_id = 'B0748JCK2J';
UPDATE products SET product_id = 'B08X3PRQTD', amazon_url = 'https://www.amazon.com/dp/B08X3PRQTD' WHERE product_id = 'B09B8Y2G2H';
