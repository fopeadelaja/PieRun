SELECT
  o.id AS order_id,
  o.user_id,
  o.status,
  o.total,
  o.fulfillment_date,
  COALESCE(
    sum(op.amount_applied) FILTER (
      WHERE
        (p.status = 'CONFIRMED' :: payment_status)
    ),
    (0) :: numeric
  ) AS applied,
  (
    o.total - COALESCE(
      sum(op.amount_applied) FILTER (
        WHERE
          (p.status = 'CONFIRMED' :: payment_status)
      ),
      (0) :: numeric
    )
  ) AS outstanding
FROM
  (
    (
      orders o
      LEFT JOIN order_payments op ON ((op.order_id = o.id))
    )
    LEFT JOIN payments p ON ((p.id = op.payment_id))
  )
WHERE
  (
    o.status = ANY (
      ARRAY ['ACCEPTED'::order_status, 'COMPLETED'::order_status]
    )
  )
GROUP BY
  o.id;