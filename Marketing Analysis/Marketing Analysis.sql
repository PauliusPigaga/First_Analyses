WITH CleanData AS --Changed formats to more useful ones.
(
  SELECT
    CASE
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d',event_date)) = 1 THEN "7 Sunday"
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d',event_date)) = 2 THEN "1 Monday"
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d',event_date)) = 3 THEN "2 Tuesday"
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d',event_date)) = 4 THEN "3 Wednesday"
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d',event_date)) = 5 THEN "4 Thursday"
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d',event_date)) = 6 THEN "5 Friday"
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d',event_date)) = 7 THEN "6 Saturday"
      END AS week_day,
    TIMESTAMP_MICROS(event_timestamp) event_timestamp,
    event_name,
    user_pseudo_id user_id,
    purchase_revenue_in_usd,
    CASE
      WHEN Campaign IN ('Data Share Promo','NewYear_V1','BlackFriday_V1','NewYear_V2','BlackFriday_V2','Holiday_V2','Holiday_V1','(data deleted)') THEN 'Campaigns'
      WHEN Campaign IN ('(referral)') THEN 'Referral'
      WHEN Campaign IN ('(organic)') THEN 'Organic'
      WHEN Campaign IN ('(direct)') THEN 'Direct'
      WHEN Campaign IN ('<Other>') Then 'Other'
      END AS Campaign
  FROM `tc-da-1.turing_data_analytics.raw_events`
)
,InactivityTime AS --Inactivity Time In Seconds
(
  SELECT
    *,
    DATETIME_DIFF(event_timestamp,LAG(event_timestamp) OVER (PARTITION BY user_id ORDER BY event_timestamp),SECOND) inactivity_time
  FROM CleanData
)
,EventsTimeDifferencePrep AS  --Calculated the time difference from one event to another by the same user.
(
  SELECT 
  *,
  LEAD(event_timestamp) OVER(PARTITION BY user_id ORDER BY event_timestamp) next_event_timestamp,
  DATETIME_DIFF(LEAD(event_timestamp) OVER(PARTITION BY user_id ORDER BY event_timestamp),event_timestamp,SECOND) as time_difference,
  FROM CleanData
)
,EventsTimeDifference AS --Using only the data where both events happened on the same day. Will use this average and standard deviation to identify new sessions.
(
  SELECT
    AVG(time_difference) average_inactivity_time,
    STDDEV(time_difference) stdev
  FROM EventsTimeDifferencePrep
  WHERE DATE(event_timestamp) = DATE(next_event_timestamp) AND time_difference <> 0
)
,SessionsPrep AS -- Information about sessions.
(
SELECT
  CONCAT(user_id,"-", ROW_NUMBER() OVER(PARTITION BY user_id ORDER BY event_timestamp))session_id,
  user_id,
  event_timestamp as session_start_at,
  LEAD(event_timestamp) OVER(PARTITION BY user_id ORDER BY event_timestamp) next_session_start_at,
  week_day,
  campaign,
  purchase_revenue_in_usd
FROM InactivityTime    
WHERE (inactivity_time > (SELECT average_inactivity_time + 1.5 * Stdev  FROM EventsTimeDifference) OR inactivity_time IS NULL) -- If the user was inactive for 4000sec next event will be a new session start.
ORDER BY user_id
)
,Sessions AS -- Session duration by Session ID.
(
  SELECT  
    session_id,
    sessionsprep.campaign,
    sessionsprep.week_day,
    DATETIME_DIFF(MAX(event_timestamp),MIN(event_timestamp),SECOND) AS duration
  FROM SessionsPrep
  LEFT JOIN InactivityTime on InactivityTime.user_id = sessionsprep.user_id
        AND InactivityTime.event_timestamp >= Sessionsprep.session_start_at
        AND (InactivityTime.event_timestamp < Sessionsprep.next_session_start_at OR Sessionsprep.next_session_start_at IS NULL)
  GROUP BY 1,2,3
)
,SessionsDuration AS -- Sessions Duration calculation by the campaign in a week. First Data Table that will be used in the analysis.
(
  SELECT
  campaign,
  week_day,
  COUNT(*) AS sessions_count,
  AVG(duration) AS average_session_duration
FROM Sessions
WHERE campaign IS NOT NULL
GROUP BY 1,2
)
,SessionsPurchasesPrep AS -- Joining SessionsID to Full Data To be able to calculate user count, average purchase revenue, and conversions by session and campaign. Also changing the campaign's name to make them clean and logical.
(
  SELECT  
    SessionsPrep.user_id,
    SessionsPrep.session_id,
    SessionsPrep.session_start_at,
    SessionsPrep.next_session_start_at,
    InactivityTime.event_timestamp,
    InactivityTime.event_name,
    InactivityTime.Purchase_revenue_in_usd,
    CASE
      WHEN InactivityTime.Campaign IN ('Data Share Promo','NewYear_V1','BlackFriday_V1','NewYear_V2','BlackFriday_V2','Holiday_V2','Holiday_V1','(data deleted)') THEN 'Campaign'
      WHEN InactivityTime.Campaign IN ('(referral)') THEN 'Referral'
      WHEN InactivityTime.Campaign IN ('(organic)') THEN 'Organic'
      WHEN InactivityTime.Campaign IN ('(direct)') THEN 'Direct'
      WHEN InactivityTime.Campaign IN ('<Other>') Then 'Other'
      END AS Campaign
  FROM SessionsPrep
  LEFT JOIN InactivityTime on InactivityTime.user_id = sessionsprep.user_id
        AND InactivityTime.event_timestamp >= Sessionsprep.session_start_at
        AND (InactivityTime.event_timestamp < Sessionsprep.next_session_start_at OR Sessionsprep.next_session_start_at is null)
)
,LastCampaignBeforeConversionPrep AS  -- Finding the last Campaign Before Conversion To include conversions to that campaign. This approach assumes that the last campaign played the most significant role in the conversion.
(    SELECT
        user_id,
        session_id,
        campaign,
        event_timestamp,
        ROW_NUMBER() OVER (PARTITION BY user_id, session_id ORDER BY event_timestamp DESC) as row_num
    FROM
        SessionsPurchasesPrep
    WHERE
        campaign IS NOT NULL
)
,LastCampaignBeforeConversion AS 
(
SELECT
    user_id,
    session_id,
    campaign,
    event_timestamp
FROM
    LastCampaignBeforeConversionPrep
WHERE
    row_num = 1
)
,SessionsPurchasesPrepFixed AS -- Joining the last campaign before conversion to full data.
(
SELECT
  SessionsPurchasesPrep.user_id,
  SessionsPurchasesPrep.session_id,
  SessionsPurchasesPrep.session_start_at,
  SessionsPurchasesPrep.next_session_start_at,
  SessionsPurchasesPrep.event_timestamp,
  SessionsPurchasesPrep.event_name,
  SessionsPurchasesPrep.Purchase_revenue_in_usd,
  LastCampaignBeforeConversion.Campaign
FROM SessionsPurchasesPrep
LEFT JOIN LastCampaignBeforeConversion USING (session_id)
)
,SessionsPurchases AS -- Calculating total user count, average purchase value, and conversions by session and campaign.Second Data Table
(
SELECT
  CAST(SPLIT(session_id,'-')[OFFSET(1)] AS INT64) session,
  campaign,
  COUNT(DISTINCT user_id) total_count,
  AVG(purchase_revenue_in_usd) avg_purchase,
  SUM(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) Conversions
FROM SessionsPurchasesPrepFixed
GROUP BY session,campaign
)
,SessionsDurationByDayPrep AS -- Session duration by day.
(
  SELECT  
    session_id,
    DATE(sessionsprep.session_start_at) event_date,
    DATETIME_DIFF(MAX(event_timestamp),MIN(event_timestamp),SECOND) AS duration
  FROM SessionsPrep
  LEFT JOIN InactivityTime on InactivityTime.user_id = sessionsprep.user_id
        AND InactivityTime.event_timestamp >= Sessionsprep.session_start_at
        AND (InactivityTime.event_timestamp < Sessionsprep.next_session_start_at OR Sessionsprep.next_session_start_at IS NULL)
  GROUP BY 1,2
)
,SessionDurationByDay AS -- Average session duration by day.
(
SELECT 
  event_date,
  AVG(duration) duration
FROM SessionsDurationByDayPrep
GROUP BY 1
ORDER BY 1
)
,BouncePrep AS -- Bounced users preparation. Most of the time session_start,first_visit, and page_view have the same timestamp, so for calculating the bounce rate, I chose page_view as the base event.
(
SELECT
    session_id,
    DATE(event_timestamp) AS visit_date,
    COUNT(event_name) AS pages_viewed
  FROM
    SessionsPurchasesPrepFixed
  WHERE event_name NOT IN ('session_start','first_visit') 
  GROUP BY 1,2
) 
,Bounce AS -- Bounced users count by day.
(
  SELECT
  visit_date event_date,
  COUNT(DISTINCT session_id) AS bounced_users
FROM
  BouncePrep
WHERE
  pages_viewed = 1
GROUP BY visit_date
)
,DailyMetricsPrep AS  -- Daily Metrics Preparation.Calculated Conversions, Average Purchase, User Count.Will join duration and bounced users on this.
(
  SELECT 
    DATE(event_timestamp) event_date,
    SUM (CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) conversions,
    ROUND(AVG(purchase_revenue_in_usd),2) avg_purchase,
    COUNT(DISTINCT user_id) user_count,
  FROM SessionsPurchasesPrepFixed a
  GROUP BY event_date
)
,DailyMetrics AS -- Daily Metrics: Date, Conversions, Average Purchase, User Count, Session Duration, Bounced Users. Third data table.
(
  SELECT
  a.*,
  b.duration,
  c.bounced_users
FROM DailyMetricsPrep a
LEFT JOIN SessionDurationByDay b USING (event_date)
LEFT JOIN Bounce c USING (event_date)
ORDER BY event_date
)
SELECT * FROM DailyMetrics