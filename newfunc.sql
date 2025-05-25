CREATE FUNCTION dbo.f_works_list_2()
RETURNS TABLE
AS
RETURN
(
    -- Inline TVF to enable optimizer inlining and eliminate scalar UDF calls
    SELECT
        w.Id_Work,
        w.Create_Date,
        w.MaterialNumber,
        w.Is_Complit,
        CONCAT(e.Surname, ' ', e.Name, COALESCE(' ' + e.Patronymic, '')) AS EmployeeFullName,
        wi.NotCompleteCount,
        wi.CompleteCount,
        s.StatusName,
        CASE WHEN w.Is_Complit = 1 THEN 1 ELSE 0 END AS Is_Print
    FROM dbo.Works AS w
    INNER JOIN dbo.Employee AS e
        ON w.Id_Employee = e.Id_Employee
    LEFT JOIN
    (
        SELECT
            Id_Work,
            SUM(CASE WHEN Is_Complit = 0 THEN 1 ELSE 0 END) AS NotCompleteCount,
            SUM(CASE WHEN Is_Complit = 1 THEN 1 ELSE 0 END) AS CompleteCount
        FROM dbo.WorkItem
        WHERE Id_Analiz NOT IN (
            SELECT Id_Analiz
            FROM dbo.Analiz
            WHERE Is_Group = 1
        )
        GROUP BY Id_Work
    ) AS wi
        ON w.Id_Work = wi.Id_Work
    LEFT JOIN dbo.WorkStatus AS s
        ON w.StatusId = s.StatusID
    WHERE w.Is_Del <> 1
);
GO
