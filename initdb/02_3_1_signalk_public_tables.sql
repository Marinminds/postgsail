---------------------------------------------------------------------------
-- singalk db public schema tables
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

CREATE SCHEMA IF NOT EXISTS public;
COMMENT ON SCHEMA public IS 'backend public functions and tables';

---------------------------------------------------------------------------
-- Table geocoders
--
-- https://github.com/CartoDB/labs-postgresql/blob/master/workshop/plpython.md
--
CREATE TABLE IF NOT EXISTS geocoders(
    name TEXT UNIQUE, 
    url TEXT, 
    reverse_url TEXT
);
-- Description
COMMENT ON TABLE
    public.geocoders
    IS 'geo service nominatim url';

INSERT INTO geocoders VALUES
('nominatim',
    NULL,
    'https://nominatim.openstreetmap.org/reverse');
-- https://photon.komoot.io/reverse?lat=48.30587233333333&lon=14.3040525
-- https://docs.mapbox.com/playground/geocoding/?search_text=-3.1457869856990897,51.35921326434686&limit=1

---------------------------------------------------------------------------
-- Tables for message template email/pushover/telegram
--
DROP TABLE IF EXISTS public.email_templates;
CREATE TABLE IF NOT EXISTS public.email_templates(
    name TEXT UNIQUE, 
    email_subject TEXT,
    email_content TEXT,
    pushover_title TEXT,
    pushover_message TEXT
);
-- Description
COMMENT ON TABLE
    public.email_templates
    IS 'email/message templates for notifications';

-- with escape value, eg: E'A\nB\r\nC'
-- https://stackoverflow.com/questions/26638615/insert-line-break-in-postgresql-when-updating-text-field
-- TODO Update notification subject for log entry to 'logbook #NB ...'
INSERT INTO public.email_templates VALUES
('logbook',
    'New Logbook Entry',
    E'Hello __RECIPIENT__,\n\nWe just wanted to let you know that you have a new entry on openplotter.cloud: "__LOGBOOK_NAME__"\r\n\r\nSee more details at __APP_URL__/log/__LOGBOOK_LINK__\n\nHappy sailing!\nThe PostgSail Team',
    'New Logbook Entry',
    E'New entry on openplotter.cloud: "__LOGBOOK_NAME__"\r\nSee more details at __APP_URL__/log/__LOGBOOK_LINK__\n'),
('new_account',
    'Welcome',
    E'Hello __RECIPIENT__,\nCongratulations!\nYou successfully created an account.\nKeep in mind to register your vessel.\nHappy sailing!',
    'Welcome',
    E'Hi!\nYou successfully created an account\nKeep in mind to register your vessel.\n'),
('new_vessel',
    'New boat',
    E'Hi!\nHow are you?\n__BOAT__ is now linked to your account.\n',
    'New boat',
    E'Hi!\nHow are you?\n__BOAT__ is now linked to your account.\n'),
('monitor_offline',
    'Boat went Offline',
    E'__BOAT__ has been offline for more than an hour\r\nFind more details at __APP_URL__/boats\n',
    'Boat went Offline',
    E'__BOAT__ has been offline for more than an hour\r\nFind more details at __APP_URL__/boats\n'),
('monitor_online',
    'Boat went Online',
    E'__BOAT__ just came online\nFind more details at __APP_URL__/boats\n',
    'Boat went Online',
    E'__BOAT__ just came online\nFind more details at __APP_URL__/boats\n'),
('new_badge',
    'New Badge!',
    E'Hello __RECIPIENT__,\nCongratulations! You have just unlocked a new badge: __BADGE_NAME__\nSee more details at __APP_URL__/badges\nHappy sailing!\nThe PostgSail Team',
    'New Badge!',
    E'Congratulations!\nYou have just unlocked a new badge: __BADGE_NAME__\nSee more details at __APP_URL__/badges\n'),
('pushover_valid',
    'Pushover integration',
    E'Hello __RECIPIENT__,\nCongratulations! You have just connect your account to Pushover.\n\nThe PostgSail Team',
    'Pushover integration!',
    E'Congratulations!\nYou have just connect your account to Pushover.\n'),
('email_otp',
    'Email verification',
    E'Hello,\nPlease active your account using the following code: __OTP_CODE__.\nThe code is valid 15 minutes.\nThe PostgSail Team',
    'Email verification',
    E'Congratulations!\nPlease validate your account. Check your email!'),
('email_valid',
    'Email verified',
    E'Hello,\nCongratulations!\nYou successfully validate your account.\nThe PostgSail Team',
    'Email verified',
    E'Hi!\nYou successfully validate your account.\n'),
('email_reset',
    'Password reset',
    E'Hello,\nYou requested a password reset. To reset your password __APP_URL__/reset-password?__RESET_QS__.\nThe PostgSail Team',
    'Password reset',
    E'You requested a password recovery. Check your email!\n'),
('telegram_otp',
    'Telegram bot',
    E'Hello,\nTo connect your account to a @postgsail_bot. Please type this verification code __OTP_CODE__ back to the bot.\nThe code is valid 15 minutes.\nThe PostgSail Team',
    'Telegram bot',
    E'Hello,\nTo connect your account to a @postgsail_bot. Check your email!\n'),
('telegram_valid',
    'Telegram bot',
    E'Hello __RECIPIENT__,\nCongratulations! You have just connect your account to your vessel, @postgsail_bot.\n\nThe PostgSail Team',
    'Telegram bot!',
    E'Congratulations!\nYou have just connect your account to your vessel, @postgsail_bot.\n'),
('no_vessel',
    'PostgSail add your boat',
    E'Hello __RECIPIENT__,\nYou created an account on PostgSail but you have not added your boat yet.\nIf you need any assistance, I would be happy to help. It is free and an open-source.\nThe PostgSail Team',
    'PostgSail next step',
    E'Hello,\nYou should create your vessel. Check your email!\n'),
('no_metadata',
    'PostgSail connect your boat',
    E'Hello __RECIPIENT__,\nYou created an account on PostgSail but you have not connected your boat yet.\nIf you need any assistance, I would be happy to help. It is free and an open-source.\nThe PostgSail Team',
    'PostgSail next step',
    E'Hello,\nYou should connect your vessel. Check your email!\n'),
('no_activity',
    'PostgSail boat inactivity',
    E'Hello __RECIPIENT__,\nWe don\'t see any activity on your account, do you need any assistance?\nIf you need any assistance, I would be happy to help. It is free and an open-source.\nThe PostgSail Team.',
    'PostgSail inactivity!',
    E'We detected inactivity. Check your email!\n'),
('deactivated',
    'PostgSail account deactivated',
    E'Hello __RECIPIENT__,\nYour account has been deactivated and all your data has been removed from PostgSail system.',
    'PostgSail deactivated!',
    E'We removed your account. Check your email!\n');

---------------------------------------------------------------------------
-- Queue handling
--
-- https://gist.github.com/kissgyorgy/beccba1291de962702ea9c237a900c79
-- https://www.depesz.com/2012/06/13/how-to-send-mail-from-database/

-- Listen/Notify way
--create function new_logbook_entry() returns trigger as $$
--begin
--    perform pg_notify('new_logbook_entry', NEW.id::text);
--    return NEW;
--END;
--$$ language plpgsql;

-- table way
CREATE TABLE IF NOT EXISTS public.process_queue (
    id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    channel TEXT NOT NULL,
    payload TEXT NOT NULL,
    ref_id TEXT NOT NULL,
    stored TIMESTAMPTZ NOT NULL,
    processed TIMESTAMPTZ DEFAULT NULL
);
-- Description
COMMENT ON TABLE
    public.process_queue
    IS 'process queue for async job';
-- Index
CREATE INDEX ON public.process_queue (channel);
CREATE INDEX ON public.process_queue (stored);
CREATE INDEX ON public.process_queue (processed);

COMMENT ON COLUMN public.process_queue.ref_id IS 'either user_id or vessel_id';

-- Function process_queue helpers
create function new_account_entry_fn() returns trigger as $new_account_entry$
begin
    insert into process_queue (channel, payload, stored, ref_id) values ('new_account', NEW.email, now(), NEW.user_id);
    return NEW;
END;
$new_account_entry$ language plpgsql;

create function new_account_otp_validation_entry_fn() returns trigger as $new_account_otp_validation_entry$
begin
    insert into process_queue (channel, payload, stored, ref_id) values ('email_otp', NEW.email, now(), NEW.user_id);
    return NEW;
END;
$new_account_otp_validation_entry$ language plpgsql;

create function new_vessel_entry_fn() returns trigger as $new_vessel_entry$
begin
    insert into process_queue (channel, payload, stored, ref_id) values ('new_vessel', NEW.owner_email, now(), NEW.vessel_id);
    return NEW;
END;
$new_vessel_entry$ language plpgsql;

create function new_vessel_public_fn() returns trigger as $new_vessel_public$
begin
    -- Update user settings with a public vessel name
    perform api.update_user_preferences_fn('{public_vessel}', regexp_replace(NEW.name, '\W+', '', 'g'));
    return NEW;
END;
$new_vessel_public$ language plpgsql;

---------------------------------------------------------------------------
-- Tables Application Settings
-- https://dba.stackexchange.com/questions/27296/storing-application-settings-with-different-datatypes#27297
-- https://stackoverflow.com/questions/6893780/how-to-store-site-wide-settings-in-a-database
-- http://cvs.savannah.gnu.org/viewvc/*checkout*/gnumed/gnumed/gnumed/server/sql/gmconfiguration.sql

CREATE TABLE IF NOT EXISTS public.app_settings (
  name TEXT NOT NULL UNIQUE,
  value TEXT NOT NULL
);
-- Description
COMMENT ON TABLE public.app_settings IS 'application settings';
COMMENT ON COLUMN public.app_settings.name IS 'application settings name key';
COMMENT ON COLUMN public.app_settings.value IS 'application settings value';

---------------------------------------------------------------------------
-- Badges description
--
DROP TABLE IF EXISTS public.badges;
CREATE TABLE IF NOT EXISTS public.badges(
    name TEXT UNIQUE, 
    description TEXT
);
-- Description
COMMENT ON TABLE
    public.badges
    IS 'Badges descriptions';

INSERT INTO badges VALUES
('Helmsman',
    'Nice work logging your first sail! You are officially a helmsman now!'),
('Wake Maker',
    'Yowzers! Welcome to the 15 knot+ club ya speed demon skipper!'),
('Explorer',
    'It looks like home is where the helm is. Cheers to 10 days away from home port!'),
('Mooring Pro',
    'It takes a lot of skill to "thread that floating needle" but seems like you have mastered mooring with 10 nights on buoy!'),
('Anchormaster',
    'Hook, line and sinker, you have this anchoring thing down! 25 days on the hook for you!'),
('Traveler todo',
    'Who needs to fly when one can sail! You are an international sailor. À votre santé!'),
('Stormtrooper',
    'Just like the elite defenders of the Empire, here you are, our braving your own hydro-empire in windspeeds above 30kts. Nice work trooper! '),
('Club Alaska',
    'Home to the bears, glaciers, midnight sun and high adventure. Welcome to the Club Alaska Captain!'),
('Tropical Traveler',
    'Look at you with your suntan, tropical drink and southern latitude!'),
('Aloha Award',
    'Ticking off over 2300 NM across the great blue Pacific makes you the rare recipient of the Aloha Award. Well done and Aloha sailor!'),
('Navigator Award',
    'Woohoo! You made it, Ticking off over 100NM in one go, well done sailor!'),
('Captain Award',
    'Congratulation, you reach over 1000NM, well done sailor!');

---------------------------------------------------------------------------
-- aistypes description
--
DROP TABLE IF EXISTS public.aistypes;
CREATE TABLE IF NOT EXISTS aistypes(
    id NUMERIC UNIQUE,
    description TEXT
);
-- Description
COMMENT ON TABLE
    public.aistypes
    IS 'aistypes AIS Ship Types, https://api.vesselfinder.com/docs/ref-aistypes.html';

INSERT INTO aistypes VALUES
(0, 'Not available (default)'),
(20, 'Wing in ground (WIG), all ships of this type'),
(21, 'Wing in ground (WIG), Hazardous category A'),
(22, 'Wing in ground (WIG), Hazardous category B'),
(23, 'Wing in ground (WIG), Hazardous category C'),
(24, 'Wing in ground (WIG), Hazardous category D'),
(25, 'Wing in ground (WIG), Reserved for future use'),
(26, 'Wing in ground (WIG), Reserved for future use'),
(27, 'Wing in ground (WIG), Reserved for future use'),
(28, 'Wing in ground (WIG), Reserved for future use'),
(29, 'Wing in ground (WIG), Reserved for future use'),
(30, 'Fishing'),
(31, 'Towing'),
(32, 'Towing: length exceeds 200m or breadth exceeds 25m'),
(33, 'Dredging or underwater ops'),
(34, 'Diving ops'),
(35, 'Military ops'),
(36, 'Sailing'),
(37, 'Pleasure Craft'),
(38, 'Reserved'),
(39, 'Reserved'),
(40, 'High speed craft (HSC), all ships of this type'),
(41, 'High speed craft (HSC), Hazardous category A'),
(42, 'High speed craft (HSC), Hazardous category B'),
(43, 'High speed craft (HSC), Hazardous category C'),
(44, 'High speed craft (HSC), Hazardous category D'),
(45, 'High speed craft (HSC), Reserved for future use'),
(46, 'High speed craft (HSC), Reserved for future use'),
(47, 'High speed craft (HSC), Reserved for future use'),
(48, 'High speed craft (HSC), Reserved for future use'),
(49, 'High speed craft (HSC), No additional information'),
(50, 'Pilot Vessel'),
(51, 'Search and Rescue vessel'),
(52, 'Tug'),
(53, 'Port Tender'),
(54, 'Anti-pollution equipment'),
(55, 'Law Enforcement'),
(56, 'Spare - Local Vessel'),
(57, 'Spare - Local Vessel'),
(58, 'Medical Transport'),
(59, 'Noncombatant ship according to RR Resolution No. 18'),
(60, 'Passenger, all ships of this type'),
(61, 'Passenger, Hazardous category A'),
(62, 'Passenger, Hazardous category B'),
(63, 'Passenger, Hazardous category C'),
(64, 'Passenger, Hazardous category D'),
(65, 'Passenger, Reserved for future use'),
(66, 'Passenger, Reserved for future use'),
(67, 'Passenger, Reserved for future use'),
(68, 'Passenger, Reserved for future use'),
(69, 'Passenger, No additional information'),
(70, 'Cargo, all ships of this type'),
(71, 'Cargo, Hazardous category A'),
(72, 'Cargo, Hazardous category B'),
(73, 'Cargo, Hazardous category C'),
(74, 'Cargo, Hazardous category D'),
(75, 'Cargo, Reserved for future use'),
(76, 'Cargo, Reserved for future use'),
(77, 'Cargo, Reserved for future use'),
(78, 'Cargo, Reserved for future use'),
(79, 'Cargo, No additional information'),
(80, 'Tanker, all ships of this type'),
(81, 'Tanker, Hazardous category A'),
(82, 'Tanker, Hazardous category B'),
(83, 'Tanker, Hazardous category C'),
(84, 'Tanker, Hazardous category D'),
(85, 'Tanker, Reserved for future use'),
(86, 'Tanker, Reserved for future use'),
(87, 'Tanker, Reserved for future use'),
(88, 'Tanker, Reserved for future use'),
(89, 'Tanker, No additional information'),
(90, 'Other Type, all ships of this type'),
(91, 'Other Type, Hazardous category A'),
(92, 'Other Type, Hazardous category B'),
(93, 'Other Type, Hazardous category C'),
(94, 'Other Type, Hazardous category D'),
(95, 'Other Type, Reserved for future use'),
(96, 'Other Type, Reserved for future use'),
(97, 'Other Type, Reserved for future use'),
(98, 'Other Type, Reserved for future use'),
(99, 'Other Type, no additional information');

---------------------------------------------------------------------------
-- MMSI MID Codes
--
DROP TABLE IF EXISTS public.mid;
CREATE TABLE IF NOT EXISTS public.mid(
    country TEXT,
    id NUMERIC UNIQUE,
    country_id INTEGER
);
-- Description
COMMENT ON TABLE
    public.mid
    IS 'MMSI MID Codes (Maritime Mobile Service Identity) Filtered by Flag of Registration, https://www.marinevesseltraffic.com/2013/11/mmsi-mid-codes-by-flag.html';

INSERT INTO mid VALUES
('Adelie Land', 501, NULL),
('Afghanistan', 401, 4),
('Alaska', 303, 840),
('Albania', 201, 8),
('Algeria', 605, 12),
('American Samoa', 559, 16),
('Andorra', 202, 20),
('Angola', 603, 24),
('Anguilla', 301, 660),
('Antigua and Barbuda', 304, 28),
('Antigua and Barbuda', 305, 28),
('Argentina', 701, 32),
('Armenia', 216, 51),
('Aruba', 307, 533),
('Ascension Island', 608, NULL),
('Australia', 503, 36),
('Austria', 203, 40),
('Azerbaijan', 423, 31),
('Azores', 204, NULL),
('Bahamas', 308, 44),
('Bahamas', 309, 44),
('Bahamas', 311, 44),
('Bahrain', 408, 48),
('Bangladesh', 405, 50),
('Barbados', 314, 52),
('Belarus', 206, 112),
('Belgium', 205, 56),
('Belize', 312, 84),
('Benin', 610, 204),
('Bermuda', 310, 60),
('Bhutan', 410, 64),
('Bolivia', 720, 68),
('Bosnia and Herzegovina', 478, 70),
('Botswana', 611, 72),
('Brazil', 710, 76),
('British Virgin Islands', 378, 92),
('Brunei Darussalam', 508, 96),
('Bulgaria', 207, 100),
('Burkina Faso', 633, 854),
('Burundi', 609, 108),
('Cambodia', 514, 116),
('Cambodia', 515, 116),
('Cameroon', 613, 120),
('Canada', 316, 124),
('Cape Verde', 617, 132),
('Cayman Islands', 319, 136),
('Central African Republic', 612, 140),
('Chad', 670, 148),
('Chile', 725, 152),
('China', 412, 156),
('China', 413, 156),
('China', 414, 156),
('Christmas Island', 516, 162),
('Cocos Islands', 523, 166),
('Colombia', 730, 170),
('Comoros', 616, 174),
('Comoros', 620, 174),
('Congo', 615, 178),
('Cook Islands', 518, 184),
('Costa Rica', 321, 188),
(E'Côte d\'Ivoire', 619, 384),
('Croatia', 238, 191),
('Crozet Archipelago', 618, NULL),
('Cuba', 323, 192),
('Cyprus', 209, 196),
('Cyprus', 210, 196),
('Cyprus', 212, 196),
('Czech Republic', 270, 203),
('Denmark', 219, 208),
('Denmark', 220, 208),
('Djibouti', 621, 262),
('Dominica', 325, 212),
('Dominican Republic', 327, 214),
('DR Congo', 676, NULL),
('Ecuador', 735, 218),
('Egypt', 622, 818),
('El Salvador', 359, 222),
('Equatorial Guinea', 631, 226),
('Eritrea', 625, 232),
('Estonia', 276, 233),
('Ethiopia', 624, 231),
('Falkland Islands', 740, 234),
('Faroe Islands', 231, NULL),
('Fiji', 520, 242),
('Finland', 230, 246),
('France', 226, 250),
('France', 227, 250),
('France', 228, 250),
('French Polynesia', 546, 260),
('Gabonese Republic', 626, 266),
('Gambia', 629, 270),
('Georgia', 213, 268),
('Germany', 211, 276),
('Germany', 218, 276),
('Ghana', 627, 288),
('Gibraltar', 236, 292),
('Greece', 237, 300),
('Greece', 239, 300),
('Greece', 240, 300),
('Greece', 241, 300),
('Greenland', 331, 304),
('Grenada', 330, 308),
('Guadeloupe', 329, 312),
('Guatemala', 332, 320),
('Guiana', 745, 324),
('Guinea', 632, 324),
('Guinea-Bissau', 630, 624),
('Guyana', 750, 328),
('Haiti', 336, 332),
('Honduras', 334, 340),
('Hong Kong', 477, 344),
('Hungary', 243, 348),
('Iceland', 251, 352),
('India', 419, 356),
('Indonesia', 525, 360),
('Iran', 422, 364),
('Iraq', 425, 368),
('Ireland', 250, 372),
('Israel', 428, 376),
('Italy', 247, 380),
('Jamaica', 339, 388),
('Japan', 431, 392),
('Japan', 432, 392),
('Jordan', 438, 400),
('Kazakhstan', 436, 398),
('Kenya', 634, 404),
('Kerguelen Islands', 635, NULL),
('Kiribati', 529, 296),
('Kuwait', 447, 414),
('Kyrgyzstan', 451, 417),
('Lao', 531, 418),
('Latvia', 275, 428),
('Lebanon', 450, 422),
('Lesotho', 644, 426),
('Liberia', 636, 430),
('Liberia', 637, 430),
('Libya', 642, 434),
('Liechtenstein', 252, 438),
('Lithuania', 277, 440),
('Luxembourg', 253, 442),
('Macao', 453, 446),
('Madagascar', 647, 450),
('Madeira', 255, NULL),
('Makedonia', 274, NULL),
('Malawi', 655, 454),
('Malaysia', 533, 458),
('Maldives', 455, 462),
('Mali', 649, 466),
('Malta', 215, 470),
('Malta', 229, 470),
('Malta', 248, 470),
('Malta', 249, 470),
('Malta', 256, 470),
('Marshall Islands', 538, 584),
('Martinique', 347, 474),
('Mauritania', 654, 478),
('Mauritius', 645, 480),
('Mexico', 345, 484),
('Micronesia', 510, 583),
('Moldova', 214, 498),
('Monaco', 254, 492),
('Mongolia', 457, 496),
('Montenegro', 262, 499),
('Montserrat', 348, 500),
('Morocco', 242, 504),
('Mozambique', 650, 508),
('Myanmar', 506, 104),
('Namibia', 659, 516),
('Nauru', 544, 520),
('Nepal', 459, 524),
('Netherlands', 244, 528),
('Netherlands', 245, 528),
('Netherlands', 246, 528),
('Netherlands Antilles', 306, NULL),
('New Caledonia', 540, 540),
('New Zealand', 512, 554),
('Nicaragua', 350, 558),
('Niger', 656, 562),
('Nigeria', 657, 566),
('Niue', 542, 570),
('North Korea', 445, 408),
('Northern Mariana Islands', 536, 580),
('Norway', 257, 578),
('Norway', 258, 578),
('Norway', 259, 578),
('Oman', 461, 512),
('Pakistan', 463, 586),
('Palau', 511, 585),
('Palestine', 443, 275),
('Panama', 351, 591),
('Panama', 352, 591),
('Panama', 353, 591),
('Panama', 354, 591),
('Panama', 355, 591),
('Panama', 356, 591),
('Panama', 357, 591),
('Panama', 370, 591),
('Panama', 371, 591),
('Panama', 372, 591),
('Panama', 373, 591),
('Papua New Guinea', 553, 598),
('Paraguay', 755, 600),
('Peru', 760, 604),
('Philippines', 548, 608),
('Pitcairn Island', 555, 612),
('Poland', 261, 616),
('Portugal', 263, 620),
('Puerto Rico', 358, 630),
('Qatar', 466, 634),
('Reunion', 660, 638),
('Romania', 264, 642),
('Russian Federation', 273, 643),
('Rwanda', 661, 646),
('Saint Helena', 665, 654),
('Saint Kitts and Nevis', 341, 659),
('Saint Lucia', 343, 662),
('Saint Paul and Amsterdam Islands', 607, NULL),
('Saint Pierre and Miquelon', 361, 666),
('Samoa', 561, 882),
('San Marino', 268, 674),
('Sao Tome and Principe', 668, 678),
('Saudi Arabia', 403, 682),
('Senegal', 663, 686),
('Serbia', 279, 688),
('Seychelles', 664, 690),
('Sierra Leone', 667, 694),
('Singapore', 563, 702),
('Singapore', 564, 702),
('Singapore', 565, 702),
('Singapore', 566, 702),
('Slovakia', 267, 703),
('Slovenia', 278, 705),
('Solomon Islands', 557, 90),
('Somalia', 666, 706),
('South Africa', 601, 710),
('South Korea', 440, 410),
('South Korea', 441, 410),
('South Sudan', 638, 728),
('Spain', 224, 724),
('Spain', 225, 724),
('Sri Lanka', 417, 144),
('St Vincent and the Grenadines', 375, 670),
('St Vincent and the Grenadines', 376, 670),
('St Vincent and the Grenadines', 377, 670),
('Sudan', 662, 729),
('Suriname', 765, 740),
('Swaziland', 669, 748),
('Sweden', 265, 752),
('Sweden', 266, 752),
('Switzerland', 269, 756),
('Syria', 468, 760),
('Taiwan', 416, 158),
('Tajikistan', 472, 762),
('Tanzania', 674, 834),
('Tanzania', 677, 834),
('Thailand', 567, 764),
('Togolese', 671, 768),
('Tonga', 570, 776),
('Trinidad and Tobago', 362, 780),
('Tunisia', 672, 788),
('Turkey', 271, 792),
('Turkmenistan', 434, 795),
('Turks and Caicos Islands', 364, 796),
('Tuvalu', 572, 798),
('Uganda', 675, 800),
('Ukraine', 272, 804),
('United Arab Emirates', 470, 784),
('United Kingdom', 232, 826),
('United Kingdom', 233, 826),
('United Kingdom', 234, 826),
('United Kingdom', 235, 826),
('Uruguay', 770, 858),
('US Virgin Islands', 379, 850),
('USA', 338, 840),
('USA', 366, 840),
('USA', 367, 840),
('USA', 368, 840),
('USA', 369, 840),
('Uzbekistan', 437, 860),
('Vanuatu', 576, 548),
('Vanuatu', 577, 548),
('Vatican City', 208, NULL),
('Venezuela', 775, 862),
('Vietnam', 574, 704),
('Wallis and Futuna Islands', 578, 876),
('Yemen', 473, 887),
('Yemen', 475, 887),
('Zambia', 678, 894),
('Zimbabwe', 679, 716);

---------------------------------------------------------------------------
--
DROP TABLE IF EXISTS public.iso3166;
CREATE TABLE IF NOT EXISTS public.iso3166(
    id INTEGER,
    country TEXT,
    alpha_2 TEXT,
    alpha_3 TEXT
);
-- Description
COMMENT ON TABLE
    public.iso3166
    IS 'This is a complete list of all country ISO codes as described in the ISO 3166 international standard. Country Codes Alpha-2 & Alpha-3 https://www.iban.com/country-codes';

INSERT INTO iso3166 VALUES
(4,'Afghanistan','AF','AFG'),
(8,'Albania','AL','ALB'),
(12,'Algeria','DZ','DZA'),
(16,'American Samoa','AS','ASM'),
(20,'Andorra','AD','AND'),
(24,'Angola','AO','AGO'),
(660,'Anguilla','AI','AIA'),
(10,'Antarctica','AQ','ATA'),
(28,'Antigua and Barbuda','AG','ATG'),
(32,'Argentina','AR','ARG'),
(51,'Armenia','AM','ARM'),
(533,'Aruba','AW','ABW'),
(36,'Australia','AU','AUS'),
(40,'Austria','AT','AUT'),
(31,'Azerbaijan','AZ','AZE'),
(44,'Bahamas (the)','BS','BHS'),
(48,'Bahrain','BH','BHR'),
(50,'Bangladesh','BD','BGD'),
(52,'Barbados','BB','BRB'),
(112,'Belarus','BY','BLR'),
(56,'Belgium','BE','BEL'),
(84,'Belize','BZ','BLZ'),
(204,'Benin','BJ','BEN'),
(60,'Bermuda','BM','BMU'),
(64,'Bhutan','BT','BTN'),
(68,E'Bolivia (Plurinational State of)','BO','BOL'),
(535,'Bonaire, Sint Eustatius and Saba','BQ','BES'),
(70,'Bosnia and Herzegovina','BA','BIH'),
(72,'Botswana','BW','BWA'),
(74,'Bouvet Island','BV','BVT'),
(76,'Brazil','BR','BRA'),
(86,E'British Indian Ocean Territory (the)','IO','IOT'),
(96,'Brunei Darussalam','BN','BRN'),
(100,'Bulgaria','BG','BGR'),
(854,'Burkina Faso','BF','BFA'),
(108,'Burundi','BI','BDI'),
(132,'Cabo Verde','CV','CPV'),
(116,'Cambodia','KH','KHM'),
(120,'Cameroon','CM','CMR'),
(124,'Canada','CA','CAN'),
(136,E'Cayman Islands (the)','KY','CYM'),
(140,E'Central African Republic (the)','CF','CAF'),
(148,'Chad','TD','TCD'),
(152,'Chile','CL','CHL'),
(156,'China','CN','CHN'),
(162,'Christmas Island','CX','CXR'),
(166,E'Cocos (Keeling) Islands (the)','CC','CCK'),
(170,'Colombia','CO','COL'),
(174,'Comoros (the)','KM','COM'),
(180,E'Congo (the Democratic Republic of the)','CD','COD'),
(178,E'Congo (the)','CG','COG'),
(184,E'Cook Islands (the)','CK','COK'),
(188,'Costa Rica','CR','CRI'),
(191,'Croatia','HR','HRV'),
(192,'Cuba','CU','CUB'),
(531,'Curaçao','CW','CUW'),
(196,'Cyprus','CY','CYP'),
(203,'Czechia','CZ','CZE'),
(384,E'Côte d\'Ivoire','CI','CIV'),
(208,'Denmark','DK','DNK'),
(262,'Djibouti','DJ','DJI'),
(212,'Dominica','DM','DMA'),
(214,E'Dominican Republic (the)','DO','DOM'),
(218,'Ecuador','EC','ECU'),
(818,'Egypt','EG','EGY'),
(222,'El Salvador','SV','SLV'),
(226,'Equatorial Guinea','GQ','GNQ'),
(232,'Eritrea','ER','ERI'),
(233,'Estonia','EE','EST'),
(748,'Eswatini','SZ','SWZ'),
(231,'Ethiopia','ET','ETH'),
(238,E'Falkland Islands (the) [Malvinas]','FK','FLK'),
(234,E'Faroe Islands (the)','FO','FRO'),
(242,'Fiji','FJ','FJI'),
(246,'Finland','FI','FIN'),
(250,'France','FR','FRA'),
(254,'French Guiana','GF','GUF'),
(258,'French Polynesia','PF','PYF'),
(260,E'French Southern Territories (the)','TF','ATF'),
(266,'Gabon','GA','GAB'),
(270,E'Gambia (the)','GM','GMB'),
(268,'Georgia','GE','GEO'),
(276,'Germany','DE','DEU'),
(288,'Ghana','GH','GHA'),
(292,'Gibraltar','GI','GIB'),
(300,'Greece','GR','GRC'),
(304,'Greenland','GL','GRL'),
(308,'Grenada','GD','GRD'),
(312,'Guadeloupe','GP','GLP'),
(316,'Guam','GU','GUM'),
(320,'Guatemala','GT','GTM'),
(831,'Guernsey','GG','GGY'),
(324,'Guinea','GN','GIN'),
(624,'Guinea-Bissau','GW','GNB'),
(328,'Guyana','GY','GUY'),
(332,'Haiti','HT','HTI'),
(334,'Heard Island and McDonald Islands','HM','HMD'),
(336,E'Holy See (the)','VA','VAT'),
(340,'Honduras','HN','HND'),
(344,'Hong Kong','HK','HKG'),
(348,'Hungary','HU','HUN'),
(352,'Iceland','IS','ISL'),
(356,'India','IN','IND'),
(360,'Indonesia','ID','IDN'),
(364,E'Iran (Islamic Republic of)','IR','IRN'),
(368,'Iraq','IQ','IRQ'),
(372,'Ireland','IE','IRL'),
(833,'Isle of Man','IM','IMN'),
(376,'Israel','IL','ISR'),
(380,'Italy','IT','ITA'),
(388,'Jamaica','JM','JAM'),
(392,'Japan','JP','JPN'),
(832,'Jersey','JE','JEY'),
(400,'Jordan','JO','JOR'),
(398,'Kazakhstan','KZ','KAZ'),
(404,'Kenya','KE','KEN'),
(296,'Kiribati','KI','KIR'),
(408,E'Korea (the Democratic People\'s Republic of)','KP','PRK'),
(410,E'Korea (the Republic of)','KR','KOR'),
(414,'Kuwait','KW','KWT'),
(417,'Kyrgyzstan','KG','KGZ'),
(418,E'Lao People\'s Democratic Republic (the)','LA','LAO'),
(428,'Latvia','LV','LVA'),
(422,'Lebanon','LB','LBN'),
(426,'Lesotho','LS','LSO'),
(430,'Liberia','LR','LBR'),
(434,'Libya','LY','LBY'),
(438,'Liechtenstein','LI','LIE'),
(440,'Lithuania','LT','LTU'),
(442,'Luxembourg','LU','LUX'),
(446,'Macao','MO','MAC'),
(450,'Madagascar','MG','MDG'),
(454,'Malawi','MW','MWI'),
(458,'Malaysia','MY','MYS'),
(462,'Maldives','MV','MDV'),
(466,'Mali','ML','MLI'),
(470,'Malta','MT','MLT'),
(584,E'Marshall Islands (the)','MH','MHL'),
(474,'Martinique','MQ','MTQ'),
(478,'Mauritania','MR','MRT'),
(480,'Mauritius','MU','MUS'),
(175,'Mayotte','YT','MYT'),
(484,'Mexico','MX','MEX'),
(583,E'Micronesia (Federated States of)','FM','FSM'),
(498,E'Moldova (the Republic of)','MD','MDA'),
(492,'Monaco','MC','MCO'),
(496,'Mongolia','MN','MNG'),
(499,'Montenegro','ME','MNE'),
(500,'Montserrat','MS','MSR'),
(504,'Morocco','MA','MAR'),
(508,'Mozambique','MZ','MOZ'),
(104,'Myanmar','MM','MMR'),
(516,'Namibia','NA','NAM'),
(520,'Nauru','NR','NRU'),
(524,'Nepal','NP','NPL'),
(528,E'Netherlands (the)','NL','NLD'),
(540,'New Caledonia','NC','NCL'),
(554,'New Zealand','NZ','NZL'),
(558,'Nicaragua','NI','NIC'),
(562,E'Niger (the)','NE','NER'),
(566,'Nigeria','NG','NGA'),
(570,'Niue','NU','NIU'),
(574,'Norfolk Island','NF','NFK'),
(580,E'Northern Mariana Islands (the)','MP','MNP'),
(578,'Norway','NO','NOR'),
(512,'Oman','OM','OMN'),
(586,'Pakistan','PK','PAK'),
(585,'Palau','PW','PLW'),
(275,'Palestine, State of','PS','PSE'),
(591,'Panama','PA','PAN'),
(598,'Papua New Guinea','PG','PNG'),
(600,'Paraguay','PY','PRY'),
(604,'Peru','PE','PER'),
(608,E'Philippines (the)','PH','PHL'),
(612,'Pitcairn','PN','PCN'),
(616,'Poland','PL','POL'),
(620,'Portugal','PT','PRT'),
(630,'Puerto Rico','PR','PRI'),
(634,'Qatar','QA','QAT'),
(807,'Republic of North Macedonia','MK','MKD'),
(642,'Romania','RO','ROU'),
(643,'Russian Federation (the)','RU','RUS'),
(646,'Rwanda','RW','RWA'),
(638,'Réunion','RE','REU'),
(652,'Saint Barthélemy','BL','BLM'),
(654,'Saint Helena, Ascension and Tristan da Cunha','SH','SHN'),
(659,'Saint Kitts and Nevis','KN','KNA'),
(662,'Saint Lucia','LC','LCA'),
(663,'Saint Martin (French part)','MF','MAF'),
(666,'Saint Pierre and Miquelon','PM','SPM'),
(670,'Saint Vincent and the Grenadines','VC','VCT'),
(882,'Samoa','WS','WSM'),
(674,'San Marino','SM','SMR'),
(678,'Sao Tome and Principe','ST','STP'),
(682,'Saudi Arabia','SA','SAU'),
(686,'Senegal','SN','SEN'),
(688,'Serbia','RS','SRB'),
(690,'Seychelles','SC','SYC'),
(694,'Sierra Leone','SL','SLE'),
(702,'Singapore','SG','SGP'),
(534,'Sint Maarten (Dutch part)','SX','SXM'),
(703,'Slovakia','SK','SVK'),
(705,'Slovenia','SI','SVN'),
(90,'Solomon Islands','SB','SLB'),
(706,'Somalia','SO','SOM'),
(710,'South Africa','ZA','ZAF'),
(239,'South Georgia and the South Sandwich Islands','GS','SGS'),
(728,'South Sudan','SS','SSD'),
(724,'Spain','ES','ESP'),
(144,'Sri Lanka','LK','LKA'),
(729,'Sudan (the)','SD','SDN'),
(740,'Suriname','SR','SUR'),
(744,'Svalbard and Jan Mayen','SJ','SJM'),
(752,'Sweden','SE','SWE'),
(756,'Switzerland','CH','CHE'),
(760,'Syrian Arab Republic','SY','SYR'),
(158,'Taiwan (Province of China)','TW','TWN'),
(762,'Tajikistan','TJ','TJK'),
(834,'Tanzania, United Republic of','TZ','TZA'),
(764,'Thailand','TH','THA'),
(626,'Timor-Leste','TL','TLS'),
(768,'Togo','TG','TGO'),
(772,'Tokelau','TK','TKL'),
(776,'Tonga','TO','TON'),
(780,'Trinidad and Tobago','TT','TTO'),
(788,'Tunisia','TN','TUN'),
(792,'Turkey','TR','TUR'),
(795,'Turkmenistan','TM','TKM'),
(796,'Turks and Caicos Islands (the)','TC','TCA'),
(798,'Tuvalu','TV','TUV'),
(800,'Uganda','UG','UGA'),
(804,'Ukraine','UA','UKR'),
(784,'United Arab Emirates (the)','AE','ARE'),
(826,'United Kingdom of Great Britain and Northern Ireland (the)','GB','GBR'),
(581,'United States Minor Outlying Islands (the)','UM','UMI'),
(840,'United States of America (the)','US','USA'),
(858,'Uruguay','UY','URY'),
(860,'Uzbekistan','UZ','UZB'),
(548,'Vanuatu','VU','VUT'),
(862,'Venezuela (Bolivarian Republic of)','VE','VEN'),
(704,'Viet Nam','VN','VNM'),
(92,'Virgin Islands (British)','VG','VGB'),
(850,'Virgin Islands (U.S.)','VI','VIR'),
(876,'Wallis and Futuna','WF','WLF'),
(732,'Western Sahara','EH','ESH'),
(887,'Yemen','YE','YEM'),
(894,'Zambia','ZM','ZMB'),
(716,'Zimbabwe','ZW','ZWE'),
(248,E'Åland Islands','AX','ALA');
