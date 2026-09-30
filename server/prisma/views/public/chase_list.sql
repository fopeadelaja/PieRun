SELECT
  u.first_name,
  u.last_name,
  u.email,
  s.order_id,
  s.fulfillment_date,
  s.outstanding
FROM
  (
    order_settlement s
    JOIN users u ON ((u.id = s.user_id))
  )
WHERE
  (
    (s.status = 'COMPLETED' :: order_status)
    AND (s.outstanding > (0) :: numeric)
  )
ORDER BY
  u.last_name,
  u.first_name,
  s.fulfillment_date;