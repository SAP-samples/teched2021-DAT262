/***************************************/
-- # Exercise 3 - Understand Vessel Motion
/***************************************/

/***************************************/
-- ## Derive Speed, Acceleration, Total Distance, and Total Time

-- Step 1: delta s, delta t, ranks, partial lines
CREATE OR REPLACE VIEW "AIS_DEMO"."V_MOTION_STATS_1" AS (
	SELECT "MMSI", "SHAPE_32616" AS "P", "TS",
		CAST("SHAPE_32616".ST_DISTANCE(LAG("SHAPE_32616", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), 'meter') AS DECIMAL(10,2)) AS "DELTA_S",
		SECONDS_BETWEEN(LAG("TS", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), "TS") AS "DELTA_T",
		ST_MAKELINE(LAG("SHAPE_32616", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), "SHAPE_32616") AS "LINE_32616",
		RANK() OVER(PARTITION BY "MMSI" ORDER BY "TS") AS "FWD_RANK", 
		RANK() OVER(PARTITION BY "MMSI" ORDER BY "TS" DESC) AS "BWD_RANK"
	FROM "AIS_DEMO"."AIS_2017"
	WHERE "MMSI" = 366780000 AND "TS" BETWEEN '2017-06-24 10:00:00' AND '2017-06-25 10:00:00'
);
SELECT * FROM "AIS_DEMO"."V_MOTION_STATS_1" ORDER BY "TS" ASC;

-- Step 2: sum up delta s and delta t, calculate speed
CREATE OR REPLACE VIEW "AIS_DEMO"."V_MOTION_STATS_2" AS (
	SELECT SUM("DELTA_S") OVER(PARTITION BY "MMSI" ORDER BY "TS" ASC) AS "TOTAL_DISTANCE",
			SUM("DELTA_T") OVER(PARTITION BY "MMSI" ORDER BY "TS" ASC) AS "TOTAL_TIMESPAN",
			"DELTA_S"/"DELTA_T" AS "SPEED_M/S", * 
		FROM "AIS_DEMO"."V_MOTION_STATS_1" 
);
SELECT * FROM "AIS_DEMO"."V_MOTION_STATS_2" ORDER BY "TS" ASC;

-- Step 3: calculate acceleration
CREATE OR REPLACE VIEW "AIS_DEMO"."V_MOTION_STATS_3" AS (
	SELECT ("SPEED_M/S"-LAG("SPEED_M/S", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS" ASC))/("DELTA_T") AS "ACCELERATION", *
		FROM "AIS_DEMO"."V_MOTION_STATS_2"
);
SELECT * FROM "AIS_DEMO"."V_MOTION_STATS_3" ORDER BY "TS" ASC;


/***************************************/
-- Now, let's wrap the 3-step logic of the SQL views above into a single function
CREATE OR REPLACE FUNCTION "AIS_DEMO"."F_MOTION_STATS" (
	IN i_filter NVARCHAR(5000)
	)
RETURNS TABLE ("MMSI" INT, "TS" TIMESTAMP, "TOTAL_DISTANCE" DECIMAL(10,2), "TOTAL_TIMESPAN" DECIMAL(10,2), "SPEED_M/S" DECIMAL(10,2), "ACCELERATION" DECIMAL(10,3), 
	"LINE_32616" ST_GEOMETRY(32616), 
	"SOG" REAL, "COG" REAL, "VESSELNAME" NVARCHAR(500), "VESSELTYPE" INT, "CARGO" INTEGER, "SHAPE_32616" ST_GEOMETRY(32616), "ID" BIGINT,
	"FWD_RANK" INT, "BWD_RANK" INT, "DELTA_T" INT, "DELTA_S" DECIMAL(10,2),
	"DATE" DATE, "WEEKDAY" INT, "HOUR" INT)
AS BEGIN
	DAT = APPLY_FILTER("AIS_DEMO"."AIS_2017", :i_filter);
	MS = SELECT *, CAST(("SPEED_M/S"-LAG("SPEED_M/S", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS" ASC))/("DELTA_T") AS DECIMAL(10,3)) AS "ACCELERATION" 
		FROM (
			SELECT	CAST(SUM("DELTA_S") OVER(PARTITION BY "MMSI" ORDER BY "TS" ASC) AS DECIMAL(10,2)) AS "TOTAL_DISTANCE",
					CAST(SUM("DELTA_T") OVER(PARTITION BY "MMSI" ORDER BY "TS" ASC) AS DECIMAL(10,2)) AS "TOTAL_TIMESPAN",
					CAST("DELTA_S"/("DELTA_T") AS DECIMAL(10,2)) AS "SPEED_M/S", 
					TO_DATE("TS") AS "DATE", WEEKDAY("TS") AS "WEEKDAY", HOUR("TS") AS "HOUR", * 
				FROM (
					SELECT "MMSI", "VESSELNAME", "VESSELTYPE", "CARGO", "ID", "SHAPE_32616", "TS", "SOG", "COG",
						ST_MAKELINE(LAG("SHAPE_32616", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), "SHAPE_32616") AS "LINE_32616",
						RANK() OVER(PARTITION BY "MMSI" ORDER BY "TS") AS "FWD_RANK", 
						RANK() OVER(PARTITION BY "MMSI" ORDER BY "TS" DESC) AS "BWD_RANK",
						CAST("SHAPE_32616".ST_DISTANCE(LAG("SHAPE_32616", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), 'meter') AS DECIMAL(10,2)) AS "DELTA_S",
						SECONDS_BETWEEN(LAG("TS", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), "TS") AS "DELTA_T"
					FROM :DAT
				)
		);
	RETURN SELECT "MMSI", "TS", "TOTAL_DISTANCE", "TOTAL_TIMESPAN", "SPEED_M/S", "ACCELERATION", "LINE_32616", "SOG", "COG", "VESSELNAME", "VESSELTYPE", "CARGO", 
		"SHAPE_32616", "ID", "FWD_RANK", "BWD_RANK", "DELTA_T", "DELTA_S", "DATE", "WEEKDAY", "HOUR"
		FROM :MS
		ORDER BY "MMSI", "FWD_RANK";
END;

-- Let's inspect some motion statistics. The string parameter needs to be a valid SQL WHERE condition on the table "AIS_DEMO"."AIS_2017"
SELECT * FROM "AIS_DEMO"."F_MOTION_STATS"(' "MMSI" = 366780000 AND "TS" BETWEEN ''2017-06-24 10:00:00'' AND ''2017-06-25 10:00:00'' ');
SELECT * FROM "AIS_DEMO"."F_MOTION_STATS"(' "VESSELTYPE" = 1004 AND "TS" BETWEEN ''2017-06-01 00:00:00'' AND ''2017-06-07 23:00:00'' ');


-- Optional: group by hour of day to get an understanding of how fast vessel go during day
SELECT HOUR("TS"), COUNT(*), COUNT(DISTINCT "MMSI"), AVG("SPEED_M/S"), MAX("SPEED_M/S")
	FROM "AIS_DEMO"."F_MOTION_STATS"(' "TS" BETWEEN ''2017-06-01 00:00:00'' AND ''2017-06-07 24:00:00'' ') WHERE "SPEED_M/S" > 0.5
	GROUP BY HOUR("TS")
	ORDER BY HOUR("TS");


-- Store some motion statistics for visualisation in QGIS
CREATE COLUMN TABLE "AIS_DEMO"."MOTION_STATS" AS (  
	SELECT * FROM "AIS_DEMO"."F_MOTION_STATS"(' "TS" BETWEEN ''2017-06-23 17:00:00'' AND ''2017-06-23 20:00:00'' ')
	WHERE "LINE_32616".ST_GEOMETRYTYPE() = 'ST_LineString'
	);

-- Inspect data
SELECT COUNT(*) FROM "AIS_DEMO"."MOTION_STATS";
SELECT COUNT(DISTINCT "MMSI") FROM "AIS_DEMO"."MOTION_STATS";
SELECT * FROM "AIS_DEMO"."MOTION_STATS" ORDER BY "SPEED_M/S" DESC;
SELECT * FROM "AIS_DEMO"."MOTION_STATS" WHERE "MMSI" = 369493730 ORDER BY "TS" ASC;

-- Optional: Database Explorer to show speed and distance for 369493730
SELECT * FROM "AIS_DEMO"."F_MOTION_STATS"(' "MMSI" = 369493730 AND "TS" BETWEEN ''2017-06-23 17:00:00'' AND ''2017-06-23 20:00:00'' ');
SELECT T1.TS, T1."SPEED_M/S", T1."ACCELERATION", T2."SPEED_M/S", T2."ACCELERATION" FROM "AIS_DEMO"."F_MOTION_STATS"(' "MMSI" = 369493730 AND "TS" BETWEEN ''2017-06-23 17:00:00'' AND ''2017-06-23 20:00:00'' ') AS T1
	LEFT JOIN "AIS_DEMO"."MOTION_STATS" AS T2 ON T1.MMSI = T2.MMSI AND T1.TS = T2.TS;





/***************************************/
-- ## Vessel Trajectories
-- Calculate individual trajectories from the motions statistics
SELECT "MMSI", ST_GeomFromText(
		'LineString M('||STRING_AGG(TO_NVARCHAR("SHAPE_32616".ST_X()||' '||"SHAPE_32616".ST_Y()||' '||SECONDS_BETWEEN('2017-05-01 00:00:00', "TS")), ',' ORDER BY "FWD_RANK")||')'
		, 32616) AS "TRAJECTORY"
	FROM "AIS_DEMO"."F_MOTION_STATS"(' "MMSI" IN (367706320, 367909800, 367730240, 366780000, 314084000) AND TS BETWEEN ''2017-06-02 5:00:00'' AND ''2017-06-03 7:00:00'' ')
	GROUP BY "MMSI"
	HAVING COUNT(*)>2;


-- Let's store the trajectories of CARGO ships for a 7 day interval
CREATE COLUMN TABLE "AIS_DEMO"."TRAJECTORIES_CARGO" (
	"MMSI" BIGINT PRIMARY KEY,
	"LINE_32616" ST_GEOMETRY(32616),
	"TS_START" TIMESTAMP,
	"TS_END" TIMESTAMP
);

SELECT "MMSI", ST_GeomFromText('LineString M('||STRING_AGG(TO_NVARCHAR("SHAPE_32616".ST_X()||' '||"SHAPE_32616".ST_Y()||' '||SECONDS_BETWEEN('2017-05-01 00:00:00', "TS")), ',' ORDER BY FWD_RANK)||')', 32616) AS "LINE_32616",
		MIN("TS") AS "TS_START", MAX("TS") AS "TS_END"
	FROM "AIS_DEMO"."F_MOTION_STATS"(' VESSELTYPE = 1004 AND TS BETWEEN ''2017-06-01 0:00:00'' AND ''2017-06-07 24:00:00'' ')
	GROUP BY "MMSI"
	HAVING COUNT(*)>2
	INTO "AIS_DEMO"."TRAJECTORIES_CARGO"("MMSI", "LINE_32616", "TS_START", "TS_END")
;


-- Let's store the trajectories of PASSENGER ships for a 7 day interval
CREATE COLUMN TABLE "AIS_DEMO"."TRAJECTORIES_PASSENGER" (
	"MMSI" BIGINT PRIMARY KEY,
	"LINE_32616" ST_GEOMETRY(32616),
	"TS_START" TIMESTAMP,
	"TS_END" TIMESTAMP
);

SELECT "MMSI", ST_GEOMFROMTEXT('LineString M('||STRING_AGG(TO_NVARCHAR("SHAPE_32616".ST_X()||' '||"SHAPE_32616".ST_Y()||' '||SECONDS_BETWEEN('2017-05-01 00:00:00', "TS")), ',' ORDER BY FWD_RANK)||')', 32616) AS "LINE_32616",
		MIN("TS") AS "TS_START", MAX("TS") AS "TS_END"
	FROM "AIS_DEMO"."F_MOTION_STATS"(' VESSELTYPE = 1012 AND TS BETWEEN ''2017-06-01 0:00:00'' AND ''2017-06-07 24:00:00''')
	GROUP BY "MMSI"
	HAVING COUNT(*)>2
	INTO "AIS_DEMO"."TRAJECTORIES_PASSENGER"("MMSI", "LINE_32616", "TS_START", "TS_END")
;










/*******************************************/
-- Dwell locations... looking for n minute intervals with no/minimal motion
-- 1 We create sliding windows, joining each observation to the ones within the previous n minutes.
-- 2 If the sum of the distances of the observations in the window is less tham 100m, we assign a 'no motion' flag
-- 3 We identify changes in motion by comparing each observation to the previous one.
-- 4 We can use the change flags to subdivide the trajectory into segments
-- 5 Finally, we can just aggregate the observations by segment 

-- Step 1: sliding windows
CREATE OR REPLACE VIEW "AIS_DEMO"."V_DWELL_LOC_1_DIST" AS (
	-- get some data from the AIS_2017 table, calculate the distance to previous observation 
	WITH DAT AS (
		SELECT "MMSI", "TS", "SHAPE_32616", 
			"SHAPE_32616".ST_DISTANCE(LAG("SHAPE_32616", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), 'meter') AS "DIST_TO_PREV",
			ST_MakeLine(LAG("SHAPE_32616", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), "SHAPE_32616") AS "LINE_32616"
			FROM "AIS_DEMO"."AIS_2017" 
			WHERE "MMSI" = 367909800 AND "TS" BETWEEN '2017-06-1 15:30:00' AND '2017-06-2 24:00:00'
		)
	SELECT T1."MMSI", T1."TS", T1."SHAPE_32616", T1."LINE_32616", T2."TS" AS "TS2", T2."SHAPE_32616" AS "SHAPE_32616_2", T2."DIST_TO_PREV",
		-- we just take the distances within each sliding window, so the oldest element adds a distance=0 to the sum
		CASE WHEN LAG(T1."TS", 1) OVER (PARTITION BY T1."MMSI", T1."TS" ORDER BY T2."TS") = T1."TS"
			THEN T2."DIST_TO_PREV" 
			ELSE 0
			END AS "DIST"
		FROM DAT AS T1 
		LEFT JOIN DAT AS T2 
			-- every observation is joined to observations that occurred up to 5*60 seconds in the past
			ON T1."TS" BETWEEN T2."TS" AND ADD_SECONDS(T2."TS", 5*60) AND T1."MMSI" = T2."MMSI"	
);

SELECT "MMSI", "TS", "TS2", "SHAPE_32616_2", "DIST_TO_PREV", "DIST" 
	FROM "AIS_DEMO"."V_DWELL_LOC_1_DIST"
	ORDER BY "MMSI", "TS", "TS2";

-- Step 2: Summing up distances
CREATE OR REPLACE VIEW "AIS_DEMO"."V_DWELL_LOC_2_DIST" AS (
	-- if the sum of the distances between the observation in the last 5 minutes is lower that 100m, we consider this a "no motion" interval
	SELECT *, CASE WHEN "SUM_DIST" < 100 THEN 'no motion' ELSE 'motion' END AS "MOTION" FROM (
		SELECT "MMSI", "TS", "SHAPE_32616", "LINE_32616", COUNT(*) AS "NUM_OBS_IN_INTERVAL", SUM("DIST") AS "SUM_DIST"
			FROM "AIS_DEMO"."V_DWELL_LOC_1_DIST"
			GROUP BY "MMSI", "TS", "SHAPE_32616", "LINE_32616"
			-- we require to have at least 3 observations in the 5 minute interval
			HAVING COUNT(*) >=3
	)
);
SELECT "MMSI", "TS", "SHAPE_32616", "NUM_OBS_IN_INTERVAL", "SUM_DIST", "MOTION" 
	FROM "AIS_DEMO"."V_DWELL_LOC_2_DIST"
	ORDER BY "MMSI", "TS" ASC;

-- Step 3: identify changes in motion
CREATE OR REPLACE VIEW "AIS_DEMO"."V_DWELL_LOC_3_DIST" AS (
	SELECT CASE 
		WHEN LAG("MOTION", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS") != "MOTION" AND "MOTION" = 'no motion' THEN 'stopped'
		WHEN LAG("MOTION", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS") != "MOTION" AND "MOTION" = 'motion' THEN 'started'
		END AS "MOTION_CHANGE", *
		FROM "AIS_DEMO"."V_DWELL_LOC_2_DIST"
);
SELECT "MMSI", "TS", "MOTION", "MOTION_CHANGE", "SHAPE_32616" 
	FROM "AIS_DEMO"."V_DWELL_LOC_3_DIST"
	ORDER BY "MMSI", "TS" ASC;

-- Step 4: segement trips using motion change markers
CREATE OR REPLACE VIEW "AIS_DEMO"."V_DWELL_LOC_4_DIST" AS (
	SELECT COUNT("MOTION_CHANGE") OVER (PARTITION BY "MMSI" ORDER BY "TS") AS "TRIP_SEGMENT", *
		FROM "AIS_DEMO"."V_DWELL_LOC_3_DIST"
);
SELECT "MMSI", "TS", "MOTION", "MOTION_CHANGE", "TRIP_SEGMENT", "SHAPE_32616" 
	FROM "AIS_DEMO"."V_DWELL_LOC_4_DIST" 
	ORDER BY "MMSI", "TS" ASC;

-- Step 5: aggregate observations by trip segment
CREATE OR REPLACE VIEW "AIS_DEMO"."V_DWELL_LOC_5_DIST" AS (
	SELECT "MMSI", MIN("TS") AS "SEGMENT_START", MAX("TS") AS "SEGMENT_END", MAX("MOTION") AS "MOTION", MIN("SUM_DIST") AS "MIN_DIST", MAX("SUM_DIST") AS "MAX_DIST", 
			COUNT(*) AS "NUM_OBS_IN_INTERVAL", "TRIP_SEGMENT", ST_COLLECTAGGR("SHAPE_32616") AS "SHAPE_32616", ST_COLLECTAGGR("LINE_32616") AS "LINE_32616" 
		FROM "AIS_DEMO"."V_DWELL_LOC_4_DIST"
		GROUP BY "MMSI", "TRIP_SEGMENT"
);
SELECT "MMSI", "SEGMENT_START", "SEGMENT_END", "MOTION", "NUM_OBS_IN_INTERVAL", "SHAPE_32616", "LINE_32616"
	FROM "AIS_DEMO"."V_DWELL_LOC_5_DIST" ORDER BY "MMSI", "TRIP_SEGMENT" ASC;


-- Wrap steps 1-5 in a function, so we can call it with a filter clause
CREATE OR REPLACE FUNCTION "AIS_DEMO"."F_TRIP_SEGMENTS_DIST" (
	IN i_filter NVARCHAR(5000), 
	IN i_intervalMin INT, 
	IN i_distanceThreshold DOUBLE
	)
RETURNS TABLE ("MMSI" INT, "SEGMENT_START" TIMESTAMP, "SEGMENT_END" TIMESTAMP, "MOTION" NVARCHAR(10), "MIN_DIST" DOUBLE, "MAX_DIST" DOUBLE, "C" INT, 
	"TRIP_SEGMENT" INT, "SHAPE_32616" ST_GEOMETRY(32616), "LINE_32616" ST_GEOMETRY(32616))
AS BEGIN
	DAT1 = APPLY_FILTER("AIS_DEMO"."AIS_2017", :i_filter);
	DAT = SELECT *, ST_MakeLine(LAG("SHAPE_32616", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), "SHAPE_32616") AS "LINE_32616", "SHAPE_32616".ST_DISTANCE(LAG("SHAPE_32616", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), 'meter') AS "DIST_TO_PREV" FROM :DAT1;
	RES = 	SELECT "MMSI", MIN("TS") AS "SEGMENT_START", MAX("TS") AS "SEGMENT_END", MAX("MOTION") AS "MOTION", MIN("SUM_DIST") AS "MIN_DIST", MAX("SUM_DIST") AS "MAX_DIST", 
		COUNT(*) AS C, "TRIP_SEGMENT", ST_COLLECTAGGR("SHAPE_32616") AS "SHAPE_32616", ST_COLLECTAGGR("LINE_32616") AS "LINE_32616"
		FROM (
			SELECT COUNT("MOTION_CHANGE") OVER (PARTITION BY "MMSI" ORDER BY "TS") AS "TRIP_SEGMENT", *
				FROM (
					SELECT CASE 
						WHEN LAG("MOTION", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS") != "MOTION" AND "MOTION" = 'no motion' THEN 'stopped'
						WHEN LAG("MOTION", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS") != "MOTION" AND "MOTION" = 'motion' THEN 'started'
						END AS "MOTION_CHANGE", *
						FROM (
							SELECT *, CASE WHEN "SUM_DIST" < :i_distanceThreshold THEN 'no motion' ELSE 'motion' END AS "MOTION" FROM (
								SELECT "MMSI", "TS", "SHAPE_32616", "LINE_32616", COUNT(*), SUM("DIST") AS "SUM_DIST"
									FROM (
										SELECT T1."MMSI", T1."TS", T1."SHAPE_32616", T1."LINE_32616", 
											CASE WHEN LAG(T1."TS", 1) OVER (PARTITION BY T1."MMSI" ORDER BY T1."TS", T2."TS") = T1."TS"
												THEN T2."DIST_TO_PREV" 
												ELSE 0
												END AS "DIST"
											FROM :DAT AS T1 
											LEFT JOIN :DAT AS T2 
												ON T1."TS" BETWEEN T2."TS" AND ADD_SECONDS(T2."TS", :i_intervalMin*60) AND T1."MMSI" = T2."MMSI"
									)
									GROUP BY "MMSI", "TS", "SHAPE_32616", "LINE_32616"
									HAVING COUNT(*) >=3
							)
						)
				)
		)
	GROUP BY "MMSI","TRIP_SEGMENT";
	RETURN SELECT * FROM :RES;
END;

SELECT "MMSI", "SEGMENT_START", "SEGMENT_END", "MOTION", "SHAPE_32616", "LINE_32616" 
	FROM "AIS_DEMO"."F_TRIP_SEGMENTS_DIST"(i_filter => ' "MMSI" = 367341010 ', i_intervalMin => 8, i_distanceThreshold => 80);
SELECT * FROM "AIS_DEMO"."F_TRIP_SEGMENTS_DIST"('VESSELTYPE = 1004 AND TS BETWEEN ''2017-06-1 00:00:00'' AND ''2017-06-30 24:00:00'' ', 5, 50);

-- store the results in a table to visualize in QGIS
CREATE COLUMN TABLE "AIS_DEMO"."TRIP_SEGMENTS" AS (
	SELECT * FROM "AIS_DEMO"."F_TRIP_SEGMENTS_DIST"('MMSI = 367341010 AND TS BETWEEN ''2017-05-1 00:00:00'' AND ''2017-06-30 06:00:00'' ', 8, 80)
);














/*******************************************/
-- Dwell locations... alternative implementation, based on speed not on distance... looking for n minute intervals with no speed
/*******************************************/

/*******************************************/
-- Step 1: get the average speed for a sliding 5 minute interval to derive motion/no motion. Require at least 3 observations.
CREATE OR REPLACE VIEW "AIS_DEMO"."V_DWELL_LOC_1" AS (
	WITH DAT AS (SELECT * FROM "AIS_DEMO"."F_MOTION_STATS"('MMSI = 367909800 AND TS BETWEEN ''2017-06-1 15:30:00'' AND ''2017-06-10 24:00:00'' '))
	SELECT "MMSI", "TS", "SHAPE_32616", "LINE_32616", COUNT(*), MIN("SPEED_M/S") AS "MIN_SPEED", MAX("SPEED_M/S") AS "MAX_SPEED", AVG("SPEED_M/S") AS "AVG_SPEED", 
		--CASE WHEN MAX("SPEED_M/S") > 1 THEN 'motion' ELSE 'no motion' END AS "MOTION" 
		CASE WHEN AVG("SPEED_M/S") < 2 AND MIN("SPEED_M/S") < 0.1 THEN 'no motion' ELSE 'motion' END AS "MOTION"
		FROM (
			SELECT T1."MMSI", T1."TS", T1."SHAPE_32616", T1."LINE_32616", T2."SPEED_M/S"
				FROM DAT AS T1 
					LEFT JOIN DAT AS T2 
					ON T1."TS" BETWEEN T2."TS" AND ADD_SECONDS(T2."TS", 5*60) AND T1."MMSI" = T2."MMSI"
				--ORDER BY T1."MMSI", T1."TS", T2."TS" ASC
			)
		GROUP BY "MMSI", "TS", "SHAPE_32616", "LINE_32616"
		HAVING COUNT(*) >=3
);
SELECT * FROM "AIS_DEMO"."V_DWELL_LOC_1" ORDER BY "MMSI", "TS" ASC;		

-- Step 2: identify changes in motion
CREATE OR REPLACE VIEW "AIS_DEMO"."V_DWELL_LOC_2" AS (
	SELECT CASE 
		WHEN LAG("MOTION", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS") != "MOTION" AND "MOTION" = 'no motion' THEN 'stopped'
		WHEN LAG("MOTION", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS") != "MOTION" AND "MOTION" = 'motion' THEN 'started'
		END AS "MOTION_CHANGE", *
		FROM "AIS_DEMO"."V_DWELL_LOC_1"
);
SELECT "MMSI", "TS", "MOTION", "MOTION_CHANGE", "SHAPE_32616" FROM "AIS_DEMO"."V_DWELL_LOC_2" ORDER BY "MMSI", "TS" ASC;

-- Step 3: segement trips using motion change markers
CREATE OR REPLACE VIEW "AIS_DEMO"."V_DWELL_LOC_3" AS (
	SELECT COUNT("MOTION_CHANGE") OVER (PARTITION BY "MMSI" ORDER BY "TS") AS "TRIP_SEGMENT", *
		FROM "AIS_DEMO"."V_DWELL_LOC_2"
);
SELECT "MMSI", "TS", "MOTION", "MOTION_CHANGE", "TRIP_SEGMENT", "SHAPE_32616" FROM "AIS_DEMO"."V_DWELL_LOC_3" ORDER BY "MMSI", "TS" ASC;

-- Step 4:
CREATE OR REPLACE VIEW "AIS_DEMO"."V_DWELL_LOC_4" AS (
	SELECT "MMSI", MIN("TS"), MAX("TS"), MAX("MOTION"), MIN("MIN_SPEED"), MAX("MAX_SPEED"), COUNT(*), "TRIP_SEGMENT", ST_COLLECTAGGR("SHAPE_32616"), ST_COLLECTAGGR("LINE_32616") 
		FROM "AIS_DEMO"."V_DWELL_LOC_3"
		GROUP BY "MMSI", "TRIP_SEGMENT"
);
SELECT * FROM "AIS_DEMO"."V_DWELL_LOC_4" ORDER BY "MMSI", "TRIP_SEGMENT" ASC;


-- Wrap the steps above into a table function
CREATE OR REPLACE FUNCTION "AIS_DEMO"."F_TRIP_SEGMENTS" (IN i_filter NVARCHAR(5000), IN i_intervalMin INT, IN i_speedThreshold DOUBLE)
RETURNS TABLE ("MMSI" INT, "SEGMENT_START" TIMESTAMP, "SEGMENT_END" TIMESTAMP, "MOTION" NVARCHAR(10), "MIN_SPEED" DOUBLE, "MAX_SPEED" DOUBLE, "AVG_SPEED" DOUBLE, "C" INT, 
	"TRIP_SEGMENT" INT, "SHAPE_32616" ST_GEOMETRY(32616), "LINE_32616" ST_GEOMETRY(32616))
AS BEGIN
	DAT = SELECT * FROM "AIS_DEMO"."F_MOTION_STATS"(:i_filter);
	RES = SELECT "MMSI", MIN(TS) AS "SEGMENT_START", MAX(TS) AS "SEGMENT_END", MAX("MOTION") AS "MOTION", 
		MIN(MIN_SPEED) AS "MIN_SPEED", MAX(MAX_SPEED) AS "MAX_SPEED", MAX(AVG_SPEED) AS "AVG_SPEED", COUNT(*) AS C, 
		"TRIP_SEGMENT", ST_COLLECTAGGR("SHAPE_32616") AS "SHAPE_32616", ST_COLLECTAGGR("LINE_32616") AS "LINE_32616" 
		FROM (
			SELECT *, COUNT("MOTION_CHANGE") OVER (PARTITION BY "MMSI" ORDER BY "TS") AS "TRIP_SEGMENT"
				FROM (		
					SELECT CASE 
							WHEN LAG("MOTION", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS") != "MOTION" AND "MOTION" = 'no motion' THEN 'stopped'
							WHEN LAG("MOTION", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS") != "MOTION" AND "MOTION" = 'motion' THEN 'started'
							END AS "MOTION_CHANGE", *
						FROM (
							SELECT "MMSI", "TS", "SHAPE_32616", "LINE_32616", COUNT(*), MIN("SPEED_M/S") AS "MIN_SPEED", MAX("SPEED_M/S") AS "MAX_SPEED", AVG("SPEED_M/S") AS "AVG_SPEED", 
								--CASE WHEN AVG("SPEED_M/S") > :i_speedThreshold AND MIN("SPEED_M/S") > 0.1 THEN 'motion' ELSE 'no motion' END AS "MOTION"
								CASE WHEN AVG("SPEED_M/S") < :i_speedThreshold AND MIN("SPEED_M/S") < 0.1 THEN 'no motion' ELSE 'motion' END AS "MOTION" 
								FROM (
									SELECT T1."MMSI", T1."TS", T1."SHAPE_32616", T1."LINE_32616", T2."SPEED_M/S"
										FROM :DAT AS T1 LEFT JOIN :DAT AS T2 ON T1."TS" BETWEEN T2."TS" AND ADD_SECONDS(T2."TS", :i_intervalMin*60) AND T1."MMSI" = T2."MMSI"
										ORDER BY T1."MMSI", T1."TS", T2."TS" ASC
								)
								GROUP BY "MMSI", "TS", "SHAPE_32616", "LINE_32616"
								HAVING COUNT(*) >=3
								ORDER BY "MMSI", "TS" ASC
						)
				)
			) GROUP BY "MMSI", "TRIP_SEGMENT" ORDER BY "MMSI", "TRIP_SEGMENT";
	RETURN SELECT * FROM :RES;
END;
SELECT * FROM "AIS_DEMO"."F_TRIP_SEGMENTS"('MMSI = 367909800 AND TS BETWEEN ''2017-06-1 00:00:00'' AND ''2017-06-10 24:00:00'' ', 10, 0.5);
SELECT * FROM "AIS_DEMO"."F_TRIP_SEGMENTS"('MMSI = 367706320 AND TS BETWEEN ''2017-06-2 06:00:00'' AND ''2017-06-03 06:00:00'' ', 5, 0.1);

