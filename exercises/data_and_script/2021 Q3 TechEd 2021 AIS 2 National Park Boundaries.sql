/***************************************/
-- # Exercise 2 - Identify Vessels within National Park Boundaries
/***************************************/

-- Import file
--	DAT262_AIS_DEMO_BOUNDARIES_TEXT.tar.gz

-- We have a table which contains the boundaries of a national park
SELECT * FROM "AIS_DEMO"."PARK_BOUNDARIES";

-- How many AIS observations and distinct vessels are located within the park boundaries?
SELECT COUNT(*), COUNT(DISTINCT "MMSI") 
	FROM "AIS_DEMO"."AIS_2017" AS D, "AIS_DEMO"."PARK_BOUNDARIES" AS B
	WHERE D."SHAPE_32616".ST_Within(B."SHAPE_32616") = 1; 

-- Or handled by a SQLScript code block
DO() BEGIN
	DECLARE BOUNDARY ST_Geometry;
	SELECT "SHAPE_32616" INTO BOUNDARY FROM "AIS_DEMO"."PARK_BOUNDARIES";
	SELECT COUNT(*), COUNT(DISTINCT "MMSI") 
	FROM "AIS_DEMO"."AIS_2017" AS D
	WHERE D."SHAPE_32616".ST_Within(:BOUNDARY) = 1;
END;

-- Which vessels and when? Get the single point observations and construct a simple route.
SELECT "MMSI", "VESSELNAME", MIN("TS"), MAX("TS"), 
		ST_CollectAggr("SHAPE_32616") AS "OBSERVATIONS", 
		ST_CollectAggr("LINE_32616") AS "ROUTE"
	FROM (
		SELECT D."MMSI", D."TS", D."VESSELNAME", D."SHAPE_32616", 
			ST_MakeLine(LAG(D."SHAPE_32616", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), D."SHAPE_32616") AS "LINE_32616" 
			FROM "AIS_DEMO"."AIS_2017" AS D, "AIS_DEMO"."PARK_BOUNDARIES" AS B
		WHERE D."SHAPE_32616".ST_Within(B."SHAPE_32616") = 1
	)
	GROUP BY "MMSI", "VESSELNAME";

-- Store data to display these observation in QGIS.
CREATE COLUMN TABLE "AIS_DEMO"."VESSELS_WITHIN_PARK_BOUNDARIES" (MMSI INT, VESSELNAME NVARCHAR(100), MINTS TIMESTAMP, MAXTS TIMESTAMP, OBSERVATIONS ST_GEOMETRY(32616),
		"ROUTE" ST_GEOMETRY(32616));
INSERT INTO "AIS_DEMO"."VESSELS_WITHIN_PARK_BOUNDARIES" (
	SELECT "MMSI", "VESSELNAME", MIN("TS"), MAX("TS"), ST_COLLECTAGGR("SHAPE_32616").ST_TRANSFORM(32616) AS "OBSERVATIONS", ST_COLLECTAGGR("LINE_32616") AS "ROUTE" FROM (
		SELECT D."MMSI", D."TS", D."VESSELNAME", D."SHAPE_32616", ST_MAKELINE(LAG(D."SHAPE_32616", 1) OVER(PARTITION BY "MMSI" ORDER BY "TS"), D."SHAPE_32616") AS "LINE_32616" 
		FROM "AIS_DEMO"."AIS_2017" AS D, "AIS_DEMO"."PARK_BOUNDARIES" AS B
		WHERE D."SHAPE_32616".ST_Within(B."SHAPE_32616") = 1
	) GROUP BY "MMSI", "VESSELNAME"
); 


