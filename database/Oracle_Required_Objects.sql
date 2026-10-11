-- ============================================================================
-- AccessGuard (ZTK Reconciler) - Oracle Database Integration Schema
-- Required Tables & Views Definition
-- Compatibility: Oracle Database 11g, 12c, 18c, 19c, 21c, 23ai (Express, SE2, EE)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ENTITY 1: MDPL_EMP_SHIFT_V (View or Table)
-- Purpose: Supplies per-employee shift work hours and maps the physical
--          ZKTeco biometric enrollment number (MACHINE_ID) to the employee.
-- AccessGuard Query:
--   SELECT MACHINE_ID, EMPLOYEE_NUMBER, SHIFT_START, SHIFT_END FROM MDPL_EMP_SHIFT_V
-- ----------------------------------------------------------------------------

-- Example Table Definition (if creating as a standalone physical table):
CREATE TABLE MDPL_EMP_SHIFT_V (
    MACHINE_ID       VARCHAR2(50)  NOT NULL, -- ZKTeco Terminal Enroll Number
    EMPLOYEE_NUMBER  VARCHAR2(50)  NOT NULL, -- Enterprise Employee Code / ID
    SHIFT_START      VARCHAR2(10)  NOT NULL, -- Format: 'HH24:MI' (e.g. '08:00')
    SHIFT_END        VARCHAR2(10)  NOT NULL, -- Format: 'HH24:MI' (e.g. '17:00')
    CONSTRAINT PK_MDPL_EMP_SHIFT PRIMARY KEY (MACHINE_ID)
);

-- Example View Definition (if mapping from an existing HR/Shift ERP schema):
/*
CREATE OR REPLACE VIEW MDPL_EMP_SHIFT_V AS
SELECT
    E.BIOMETRIC_ENROLL_ID   AS MACHINE_ID,
    E.EMP_CODE              AS EMPLOYEE_NUMBER,
    TO_CHAR(S.START_TIME, 'HH24:MI') AS SHIFT_START,
    TO_CHAR(S.END_TIME,   'HH24:MI') AS SHIFT_END
FROM HR_EMPLOYEES E
JOIN HR_SHIFTS S ON E.SHIFT_ID = S.SHIFT_ID;
*/

-- ----------------------------------------------------------------------------
-- ENTITY 2: PP_EMP_ATT_MST_DW (View or Table)
-- Purpose: Attendance transaction log containing biometric check-in punches.
-- AccessGuard Query:
--   SELECT AM_EMPNO, AM_TIME, AM_SHIFT
--   FROM PP_EMP_ATT_MST_DW
--   WHERE AM_TIME LIKE :targetDate || '%' AND AM_SHIFT IN ('1', '3')
-- ----------------------------------------------------------------------------

-- Example Table Definition:
CREATE TABLE PP_EMP_ATT_MST_DW (
    AM_EMPNO   VARCHAR2(50)  NOT NULL, -- Employee Number matching EMPLOYEE_NUMBER
    AM_TIME    VARCHAR2(20)  NOT NULL, -- Format: 'YYYY/MM/DD HH24:MI' (e.g. '2026/10/11 08:04')
    AM_SHIFT   VARCHAR2(10)  NOT NULL  -- Event code: '1' = Check-In, '3' = Break-In
);

CREATE INDEX IDX_PP_ATT_EMP_TIME ON PP_EMP_ATT_MST_DW (AM_TIME, AM_SHIFT, AM_EMPNO);

-- ----------------------------------------------------------------------------
-- VERIFICATION QUERIES FOR CLIENT DBA
-- Run these queries after creating views/tables to ensure AccessGuard will connect
-- and fetch data without error.
-- ----------------------------------------------------------------------------

-- 1. Check Shift View schema and sample row
SELECT MACHINE_ID, EMPLOYEE_NUMBER, SHIFT_START, SHIFT_END 
FROM MDPL_EMP_SHIFT_V 
WHERE ROWNUM <= 5;

-- 2. Check Attendance Punch table schema and sample arrival row
SELECT AM_EMPNO, AM_TIME, AM_SHIFT 
FROM PP_EMP_ATT_MST_DW 
WHERE AM_SHIFT IN ('1', '3') 
  AND ROWNUM <= 5;

-- 3. Verify that AM_TIME strings can parse to DATE without throwing ORA-01843
SELECT 
    AM_EMPNO, 
    TO_DATE(AM_TIME, 'YYYY/MM/DD HH24:MI') AS PARSED_DATE,
    AM_SHIFT
FROM PP_EMP_ATT_MST_DW
WHERE ROWNUM <= 5;
