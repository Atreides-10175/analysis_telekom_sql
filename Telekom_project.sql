with
-- 1. Таблица по звонкам (ежемесячная статистика)
table_calls_monthly (user_id, year_month_call, duration_call_monthly)
as (
  select  user_id,
          strftime('%Y-%m', call_date) as year_month_call,
          sum(ceil(duration)) as duration_call_monthly
  from calls
  GROUP by user_id, strftime('%Y-%m', call_date)
  ),
-- 2. Добавляем тарифные планы к звонкам
table_calls_costs_tariff (user_id, year_month_call,
                        duration_call_monthly, tariff)
AS (
  SELECT table_calls_monthly.user_id
        ,table_calls_monthly.year_month_call
        ,table_calls_monthly.duration_call_monthly
        ,users.tariff
  from table_calls_monthly
  INNER join users
  on table_calls_monthly.user_id = users.user_id  
  ),
-- 3. Расчет стоимости звонков с учетом тарифов
table_calls_costs_tariff_final
AS (
   SELECT
          table_calls_costs_tariff.user_id,
          table_calls_costs_tariff.year_month_call,
          table_calls_costs_tariff.duration_call_monthly,
          table_calls_costs_tariff.tariff,
          tariffs.minutes_included,
          tariffs.rub_per_minute,
          tariffs.rub_monthly_fee,
          tariffs.rub_monthly_fee + tariffs.rub_per_minute*max(0, table_calls_costs_tariff.duration_call_monthly-
                                                               tariffs.minutes_included) AS calls_monthly_costs
   FROM table_calls_costs_tariff
   INNER JOIN tariffs
   ON tariffs.tariff_name = table_calls_costs_tariff.tariff  
),
-- 4. Итоговая выручка по звонкам
table_calls_profit_final
AS
  (
    SELECT tariff,
           sum(calls_monthly_costs) as full_costs_calls 
    FROM table_calls_costs_tariff_final
    GROUP BY tariff 
  ),
-- 5. Таблица по SMS (ежемесячная статистика)
table_sms_monthly (user_id, year_month_sms, sms_count_monthly)
as (
  select  user_id,
          strftime('%Y-%m', message_date) as year_month_sms,
          count(*) as sms_count_monthly
  from messages
  GROUP by user_id, strftime('%Y-%m', message_date)
  ),
-- 6. Добавляем тарифные планы к SMS
table_sms_costs_tariff (user_id, year_month_sms, sms_count_monthly, tariff)
AS (
  SELECT table_sms_monthly.user_id
        ,table_sms_monthly.year_month_sms
        ,table_sms_monthly.sms_count_monthly
        ,users.tariff
  from table_sms_monthly
  INNER join users
  on table_sms_monthly.user_id = users.user_id  
  ),
-- 7. Расчет стоимости SMS с учетом тарифов
table_sms_costs_tariff_final
AS (
   SELECT
          table_sms_costs_tariff.user_id,
          table_sms_costs_tariff.year_month_sms,
          table_sms_costs_tariff.sms_count_monthly,
          table_sms_costs_tariff.tariff,
          tariffs.messages_included,
          tariffs.rub_per_message,
          tariffs.rub_per_message*max(0, table_sms_costs_tariff.sms_count_monthly-
                                      tariffs.messages_included) AS sms_monthly_costs
   FROM table_sms_costs_tariff
   INNER JOIN tariffs
   ON tariffs.tariff_name = table_sms_costs_tariff.tariff  
),
-- 8. Итоговая выручка по SMS
table_sms_profit_final
AS
  (
    SELECT tariff,
           sum(sms_monthly_costs) as full_costs_sms 
    FROM table_sms_costs_tariff_final
    GROUP BY tariff 
  ),
-- 9. Таблица по интернету (ежемесячная статистика)
table_internet_monthly (user_id, year_month, sum_mb_used)
as (
  select  user_id,
          strftime('%Y-%m', session_date) as year_month,
          sum(ceil(mb_used)) as sum_mb_used
  from internet
  GROUP by user_id, strftime('%Y-%m', session_date)
  ),
-- 10. Добавляем тарифные планы к интернету
table_internet_monthly_tariff (user_id, year_month, sum_mb_used, tariff)
AS (
   SELECT
          table_internet_monthly.user_id,
          table_internet_monthly.year_month,
          table_internet_monthly.sum_mb_used,
          users.tariff
   FROM table_internet_monthly
   INNER JOIN users
   ON users.user_id = table_internet_monthly.user_id  
  ),
-- 11. Расчет стоимости интернета с учетом тарифов
table_internet_monthly_tariff_limit
AS
 (
  SELECT
         table_internet_monthly_tariff.user_id,
         table_internet_monthly_tariff.year_month,
         table_internet_monthly_tariff.sum_mb_used,
         table_internet_monthly_tariff.tariff,
         tariffs.mb_per_month_included,
         tariffs.rub_per_gb,
         tariffs.rub_per_gb * max(0, 
         ceil(1.0*(table_internet_monthly_tariff.sum_mb_used - tariffs.mb_per_month_included)/1024)) AS internet_monthly_costs
  FROM table_internet_monthly_tariff
  INNER JOIN tariffs
  ON tariffs.tariff_name = table_internet_monthly_tariff.tariff 
 ),
-- 12. Итоговая выручка по интернету
table_internet_profit_final
AS (
   SELECT tariff,
          sum(internet_monthly_costs) AS internet_profit
   FROM table_internet_monthly_tariff_limit
   GROUP BY tariff
   ),
-- 13. Объединяем всю выручку по всем услугам
total_revenue_data
AS (
  SELECT 
    c.tariff,
    c.full_costs_calls as calls_revenue,
    s.full_costs_sms as sms_revenue,
    i.internet_profit as internet_revenue,
    (c.full_costs_calls + s.full_costs_sms + i.internet_profit) as total_revenue
  FROM table_calls_profit_final c
  INNER JOIN table_sms_profit_final s ON c.tariff = s.tariff
  INNER JOIN table_internet_profit_final i ON c.tariff = i.tariff
)
-- 14. Финальный результат - сравнение выручки по тарифам
SELECT 
  tariff,
  calls_revenue,
  sms_revenue,
  internet_revenue,
  total_revenue,
  CASE 
    WHEN total_revenue = max_total THEN 'Наибольшая выручка'
    ELSE 'Меньшая выручка'
  END as revenue_comparison
FROM total_revenue_data
CROSS JOIN (SELECT MAX(total_revenue) as max_total FROM total_revenue_data)
ORDER BY total_revenue DESC;
