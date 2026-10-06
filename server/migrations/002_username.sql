BEGIN;
DROP VIEW chase_list;
ALTER TABLE users DROP COLUMN email;
ALTER TABLE users ADD COLUMN username TEXT NOT NULL check (length(trim(username)) > 0);
CREATE UNIQUE INDEX users_username_unique ON users ((lower(username)));
CREATE VIEW chase_list AS
SELECT u.first_name,u.last_name, u.username, s.order_id, s.fulfillment_date, s.outstanding
FROM order_settlement s
JOIN users u ON u.id = s.user_id
WHERE s.status = 'COMPLETED' AND s.outstanding > 0
ORDER BY u.last_name, u.first_name, s.fulfillment_date;
COMMIT;