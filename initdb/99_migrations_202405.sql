---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration May 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
	VALUES ('account_disable','PostgSail Account disable',E'Hello __RECIPIENT__,\nSorry!Your account is disable. Please contact me to solve the issue.','PostgSail Account disable!',E'Sorry!\nYour account is disable. Please contact me to solve the issue.');

-- Check if user is disable due to abuse
create or replace function
api.login(in email text, in pass text) returns auth.jwt_token as $$
declare
  _role name;
  result auth.jwt_token;
  app_jwt_secret text;
  _email_valid boolean := false;
  _email text := email;
  _user_id text := null;
  _user_disable boolean := false;
  headers   json := current_setting('request.headers', true)::json;
  client_ip text := coalesce(headers->>'x-client-ip', NULL);
begin
  -- check email and password
  select auth.user_role(email, pass) into _role;
  if _role is null then
    -- HTTP/403
    --raise invalid_password using message = 'invalid user or password';
    -- HTTP/401
    raise insufficient_privilege using message = 'invalid user or password';
  end if;

  -- Check if user is disable due to abuse
  SELECT preferences['disable'],user_id INTO _user_disable,_user_id
              FROM auth.accounts a
              WHERE a.email = _email;
  IF _user_disable is True then
  	-- due to the raise, the insert is never committed.
    --INSERT INTO process_queue (channel, payload, stored, ref_id)
    --  VALUES ('account_disable', _email, now(), _user_id);
    RAISE sqlstate 'PT402' using message = 'Account disable, contact us',
            detail = 'Quota exceeded',
            hint = 'Upgrade your plan';
  END IF;

  -- Check email_valid and generate OTP
  SELECT preferences['email_valid'],user_id INTO _email_valid,_user_id
              FROM auth.accounts a
              WHERE a.email = _email;
  IF _email_valid is null or _email_valid is False THEN
    INSERT INTO process_queue (channel, payload, stored, ref_id)
      VALUES ('email_otp', _email, now(), _user_id);
  END IF;

  -- Track IP per user to avoid abuse
  RAISE WARNING 'api.login debug: [%],[%]', client_ip, login.email;
  IF client_ip IS NOT NULL THEN
    UPDATE auth.accounts a SET preferences = jsonb_recursive_merge(a.preferences, jsonb_build_object('ip', client_ip)) WHERE a.email = login.email;
  END IF;

  -- Get app_jwt_secret
  SELECT value INTO app_jwt_secret
    FROM app_settings
    WHERE name = 'app.jwt_secret';

  --RAISE WARNING 'api.login debug: [%],[%],[%]', app_jwt_secret, _role, login.email;
  -- Generate jwt
  select jwt.sign(
  --    row_to_json(r), ''
  --    row_to_json(r)::json, current_setting('app.jwt_secret')::text
      row_to_json(r)::json, app_jwt_secret
    ) as token
    from (
      select _role as role, login.email as email,  -- TODO replace with user_id
    --  select _role as role, user_id as uid, -- add support in check_jwt
         extract(epoch from now())::integer + 60*60 as exp
    ) r
    into result;
  return result;
end;
$$ language plpgsql security definer;

-- Add moorage name to view
DROP VIEW IF EXISTS api.moorages_stays_view;
CREATE OR REPLACE VIEW api.moorages_stays_view WITH (security_invoker=true,security_barrier=true) AS
    select
        _to.name AS _to_name,
        _to.id AS _to_id,
        _to._to_time,
        _from.id AS _from_id,
        _from.name AS _from_name,
        _from._from_time,
        s.stay_code,s.duration,m.id,m.name
        FROM api.stays_at sa, api.moorages m, api.stays s
        LEFT JOIN api.logbook AS _from ON _from._from_time = s.departed
        LEFT JOIN api.logbook AS _to ON _to._to_time = s.arrived
        WHERE s.departed IS NOT NULL
            AND s.name IS NOT NULL
            AND s.stay_code = sa.stay_code
            AND s.moorage_id = m.id
        ORDER BY _to._to_time DESC;
-- Description
COMMENT ON VIEW
    api.moorages_stays_view
    IS 'Moorages stay listing web view';

-- Create a merge_logbook_fn
CREATE OR REPLACE FUNCTION api.merge_logbook_fn(IN id_start integer, IN id_end integer) RETURNS void AS $merge_logbook$
    DECLARE
        logbook_rec_start record;
        logbook_rec_end record;
        log_name text;
        avg_rec record;
        geo_rec record;
        geojson jsonb;
        extra_json jsonb;
    BEGIN
        -- If id_start or id_end is not NULL
        IF (id_start IS NULL OR id_start < 1) OR (id_end IS NULL OR id_end < 1) THEN
            RAISE WARNING '-> merge_logbook_fn invalid input % %', id_start, id_end;
            RETURN;
        END IF;
        -- If id_end is lower than id_start
        IF id_end <= id_start THEN
            RAISE WARNING '-> merge_logbook_fn invalid input % < %', id_end, id_start;
            RETURN;
        END IF;
        -- Get the start logbook record with all necessary fields exist
        SELECT * INTO logbook_rec_start
            FROM api.logbook
            WHERE active IS false
                AND id = id_start
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec_start.vessel_id IS NULL THEN
            RAISE WARNING '-> merge_logbook_fn invalid logbook %', id_start;
            RETURN;
        END IF;
        -- Get the end logbook record with all necessary fields exist
        SELECT * INTO logbook_rec_end
            FROM api.logbook
            WHERE active IS false
                AND id = id_end
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec_end.vessel_id IS NULL THEN
            RAISE WARNING '-> merge_logbook_fn invalid logbook %', id_end;
            RETURN;
        END IF;

       	RAISE WARNING '-> merge_logbook_fn logbook start:% end:%', id_start, id_end;
        PERFORM set_config('vessel.id', logbook_rec_start.vessel_id, false);
   
        -- Calculate logbook data average and geo
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := logbook_update_avg_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);
        geo_rec := logbook_update_geom_distance_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);

	    -- Process `propulsion.*.runTime` and `navigation.log`
        -- Calculate extra json
        extra_json := logbook_update_extra_json_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);

       	-- generate logbook name, concat _from_location and _to_location from moorage name
       	SELECT CONCAT(logbook_rec_start._from, ' to ', logbook_rec_end._to) INTO log_name;
        RAISE NOTICE 'Updating valid logbook entry logbook id:[%] start:[%] end:[%]', logbook_rec_start.id, logbook_rec_start._from_time, logbook_rec_end._to_time;
        UPDATE api.logbook
            SET
                -- Update the start logbook with the new calculate metrics
            	duration = (logbook_rec_end._to_time::TIMESTAMPTZ - logbook_rec_start._from_time::TIMESTAMPTZ),
                avg_speed = avg_rec.avg_speed,
                max_speed = avg_rec.max_speed,
                max_wind_speed = avg_rec.max_wind_speed,
                name = log_name,
                track_geom = geo_rec._track_geom,
                distance = geo_rec._track_distance,
                extra = extra_json,
                -- Set _to metrics from end logbook
                _to = logbook_rec_end._to,
                _to_moorage_id = logbook_rec_end._to_moorage_id,
                _to_lat = logbook_rec_end._to_lat,
                _to_lng = logbook_rec_end._to_lng,
                _to_time = logbook_rec_end._to_time
            WHERE id = logbook_rec_start.id;

        -- GeoJSON require track_geom field
        geojson := logbook_update_geojson_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);
        UPDATE api.logbook
            SET
                track_geojson = geojson
            WHERE id = logbook_rec_start.id;
 
        -- Update logbook mark for deletion
        UPDATE api.logbook
            SET notes = 'mark for deletion'
            WHERE id = logbook_rec_end.id;
        -- Update related stays mark for deletion
        UPDATE api.stays
            SET notes = 'mark for deletion'
            WHERE arrived = logbook_rec_start._to_time;
       -- Update related moorages mark for deletion
        UPDATE api.moorages
            SET notes = 'mark for deletion'
            WHERE id = logbook_rec_start._to_moorage_id;

        -- Clean up, remove invalid logbook and stay, moorage entry
        DELETE FROM api.logbook WHERE id = logbook_rec_end.id;
        RAISE WARNING '-> merge_logbook_fn delete logbook id [%]', logbook_rec_end.id;
        DELETE FROM api.stays WHERE arrived = logbook_rec_start._to_time;
        RAISE WARNING '-> merge_logbook_fn delete stay arrived [%]', logbook_rec_start._to_time;
        DELETE FROM api.moorages WHERE id = logbook_rec_start._to_moorage_id;
        RAISE WARNING '-> merge_logbook_fn delete moorage id [%]', logbook_rec_start._to_moorage_id;
    END;
$merge_logbook$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.merge_logbook_fn
    IS 'Merge 2 logbook by id, from the start of the lower log id and the end of the higher log id, update the calculate data as well (avg, geojson)';

-- Add tags to view
DROP VIEW IF EXISTS api.logs_view;
CREATE OR REPLACE VIEW api.logs_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id,
    name,
    _from AS "from",
    _from_time AS started,
    _to AS "to",
    _to_time AS ended,
    distance,
    duration,
    _from_moorage_id,
    _to_moorage_id,
    extra->'tags' AS tags
   FROM api.logbook l
  WHERE name IS NOT NULL AND _to_time IS NOT NULL
  ORDER BY _from_time DESC;
COMMENT ON VIEW api.logs_view IS 'Logs web view';

-- Update a logbook with avg wind speed
DROP FUNCTION IF EXISTS public.logbook_update_avg_fn;
CREATE OR REPLACE FUNCTION public.logbook_update_avg_fn(
    IN _id integer, 
    IN _start TEXT, 
    IN _end TEXT,
    OUT avg_speed double precision,
    OUT max_speed double precision,
    OUT max_wind_speed double precision,
    OUT avg_wind_speed double precision,
    OUT count_metric integer
) AS $logbook_update_avg$
    BEGIN
        RAISE NOTICE '-> logbook_update_avg_fn calculate avg for logbook id=%, start:"%", end:"%"', _id, _start, _end;
        SELECT AVG(speedoverground), MAX(speedoverground), MAX(windspeedapparent), AVG(windspeedapparent), COUNT(*) INTO
                avg_speed, max_speed, max_wind_speed, avg_wind_speed, count_metric
            FROM api.metrics m
            WHERE m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time >= _start::TIMESTAMPTZ
                AND m.time <= _end::TIMESTAMPTZ
                AND vessel_id = current_setting('vessel.id', false);
        RAISE NOTICE '-> logbook_update_avg_fn avg for logbook id=%, avg_speed:%, max_speed:%, avg_wind_speed:%, max_wind_speed:%, count:%', _id, avg_speed, max_speed, avg_wind_speed, max_wind_speed, count_metric;
    END;
$logbook_update_avg$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_avg_fn
    IS 'Update logbook details with calculate average and max data, AVG(speedOverGround), MAX(speedOverGround), MAX(windspeedapparent), count_metric';

-- Update pending new logbook from process queue
DROP FUNCTION IF EXISTS process_logbook_queue_fn;
CREATE OR REPLACE FUNCTION process_logbook_queue_fn(IN _id integer) RETURNS void AS $process_logbook_queue$
    DECLARE
        logbook_rec record;
        from_name text;
        to_name text;
        log_name text;
        from_moorage record;
        to_moorage record;
        avg_rec record;
        geo_rec record;
        log_settings jsonb;
        user_settings jsonb;
        geojson jsonb;
        extra_json jsonb;
    BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_logbook_queue_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Get the logbook record with all necessary fields exist
        SELECT * INTO logbook_rec
            FROM api.logbook
            WHERE active IS false
                AND id = _id
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> process_logbook_queue_fn invalid logbook %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', logbook_rec.vessel_id, false);
        --RAISE WARNING 'public.process_logbook_queue_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);

        -- Calculate logbook data average and geo
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := logbook_update_avg_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        geo_rec := logbook_update_geom_distance_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);

        -- Do we have an existing moorage within 300m of the new log
        -- generate logbook name, concat _from_location and _to_location from moorage name
        from_moorage := process_lat_lon_fn(logbook_rec._from_lng::NUMERIC, logbook_rec._from_lat::NUMERIC);
        to_moorage := process_lat_lon_fn(logbook_rec._to_lng::NUMERIC, logbook_rec._to_lat::NUMERIC);
        SELECT CONCAT(from_moorage.moorage_name, ' to ' , to_moorage.moorage_name) INTO log_name;

        -- Process `propulsion.*.runTime` and `navigation.log`
        -- Calculate extra json
        extra_json := logbook_update_extra_json_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        -- add the avg_wind_speed
        extra_json := extra_json || jsonb_build_object('avg_wind_speed', avg_rec.avg_wind_speed);

        RAISE NOTICE 'Updating valid logbook entry logbook id:[%] start:[%] end:[%]', logbook_rec.id, logbook_rec._from_time, logbook_rec._to_time;
        UPDATE api.logbook
            SET
                duration = (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ),
                avg_speed = avg_rec.avg_speed,
                max_speed = avg_rec.max_speed,
                max_wind_speed = avg_rec.max_wind_speed,
                _from = from_moorage.moorage_name,
                _from_moorage_id = from_moorage.moorage_id,
                _to_moorage_id = to_moorage.moorage_id,
                _to = to_moorage.moorage_name,
                name = log_name,
                track_geom = geo_rec._track_geom,
                distance = geo_rec._track_distance,
                extra = extra_json,
                notes = NULL -- reset pre_log process
            WHERE id = logbook_rec.id;

        -- GeoJSON require track_geom field
        geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        UPDATE api.logbook
            SET
                track_geojson = geojson
            WHERE id = logbook_rec.id;

        -- Prepare notification, gather user settings
        SELECT json_build_object('logbook_name', log_name, 'logbook_link', logbook_rec.id) into log_settings;
        user_settings := get_user_settings_from_vesselid_fn(logbook_rec.vessel_id::TEXT);
        SELECT user_settings::JSONB || log_settings::JSONB into user_settings;
        RAISE NOTICE '-> debug process_logbook_queue_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        RAISE NOTICE '-> debug process_logbook_queue_fn log_settings [%]', log_settings;
        -- Send notification
        PERFORM send_notification_fn('logbook'::TEXT, user_settings::JSONB);
        -- Process badges
        RAISE NOTICE '-> debug process_logbook_queue_fn user_settings [%]', user_settings->>'email'::TEXT;
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        PERFORM badges_logbook_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
        PERFORM badges_geom_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
    END;
$process_logbook_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_logbook_queue_fn
    IS 'Update logbook details when completed, logbook_update_avg_fn, logbook_update_geom_distance_fn, reverse_geocode_py_fn';

-- Allow to run query for user_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO grafana;

-- Allow to run query for user_role
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO grafana;

-- CRON for signalk plugin upgrade
-- The goal is to avoid error from old plugin version by enforcing upgrade.
-- ERROR:  there is no unique or exclusion constraint matching the ON CONFLICT specification
-- "POST /metadata?on_conflict=client_id HTTP/1.1" 400 137 "-" "postgsail.signalk v0.0.9"
CREATE FUNCTION public.cron_process_skplugin_upgrade_fn() RETURNS void AS $skplugin_upgrade$
DECLARE
    skplugin_upgrade_rec record;
    user_settings jsonb;
BEGIN
    -- Check for signalk plugin version
    RAISE NOTICE 'cron_process_plugin_upgrade_fn';
    FOR skplugin_upgrade_rec in
        SELECT
            v.owner_email,m.name,m.vessel_id,m.plugin_version,a.first
            FROM api.metadata m
            LEFT JOIN auth.vessels v ON v.vessel_id = m.vessel_id
            LEFT JOIN auth.accounts a ON v.owner_email = a.email
            WHERE m.plugin_version <= '0.3.0'
    LOOP
        RAISE NOTICE '-> cron_process_skplugin_upgrade_rec_fn for [%]', skplugin_upgrade_rec;
        SELECT json_build_object('email', skplugin_upgrade_rec.owner_email, 'recipient', skplugin_upgrade_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_skplugin_upgrade_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('skplugin_upgrade'::TEXT, user_settings::JSONB);
    END LOOP;
END;
$skplugin_upgrade$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_skplugin_upgrade_fn
    IS 'init by pg_cron, check for signalk plugin version and notify for upgrade';

INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
	VALUES ('skplugin_upgrade','PostgSail Signalk plugin upgrade',E'Hello __RECIPIENT__,\nPlease upgrade your postgsail signalk plugin. Be sure to contact me if you encounter any issue.','PostgSail Signalk plugin upgrade!',E'Please upgrade your postgsail signalk plugin.');

-- Update version
UPDATE public.app_settings
	SET value='0.7.3'
	WHERE "name"='app.version';

\c postgres

-- Notifications/Reminders for old signalk plugin
-- At 08:06 on Sunday.
-- At 08:06 on every 4th day-of-month if it's on Sunday.
SELECT cron.schedule('cron_skplugin_upgrade', '6 8 */4 * 0', 'select public.cron_process_skplugin_upgrade_fn()');
UPDATE cron.job	SET database = 'postgres' WHERE jobname = 'cron_skplugin_upgrade';
