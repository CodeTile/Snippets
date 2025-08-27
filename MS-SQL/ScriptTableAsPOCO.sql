DECLARE @PocoName NVARCHAR(100) = 'Address';
DECLARE @SchemaName NVARCHAR(128) = 'Person';
DECLARE @TableName NVARCHAR(128) = 'emailaddress';
DECLARE @RowLimit INT = 30;
--=================================================
IF OBJECT_ID('tempdb..#TempResults') IS NOT NULL
    DROP TABLE #TempResults;


DECLARE @SQL NVARCHAR(MAX) = 'var list = new List<' + @PocoName + '> {' + CHAR(13) + CHAR(10);

-- Get column metadata
DECLARE @Columns TABLE (
    ColumnName NVARCHAR(128),
    DataType NVARCHAR(128)
);

INSERT INTO @Columns
SELECT c.name, t.name
FROM sys.columns c
JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName));

-- Build column list
DECLARE @ColumnList NVARCHAR(MAX);
SELECT @ColumnList = STRING_AGG(QUOTENAME(ColumnName), ', ') FROM @Columns;

-- Create temp table with dynamic columns
CREATE TABLE #TempResults (RowNum INT IDENTITY(1,1));

DECLARE @AddColumnSQL NVARCHAR(MAX);
SELECT @AddColumnSQL = STRING_AGG('ALTER TABLE #TempResults ADD [' + ColumnName + '] NVARCHAR(MAX);', CHAR(13) + CHAR(10))
FROM @Columns;
EXEC(@AddColumnSQL);


-- Insert data
DECLARE @InsertSQL NVARCHAR(MAX) = '
INSERT INTO #TempResults (' + @ColumnList + ')
SELECT TOP (' + CAST(@RowLimit AS NVARCHAR) + ') ' + @ColumnList + '
FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
EXEC(@InsertSQL);

-- Generate C# object list
DECLARE @RowCount INT = (SELECT COUNT(*) FROM #TempResults);
DECLARE @i INT = 1;

WHILE @i <= @RowCount
BEGIN
    DECLARE @RowText NVARCHAR(MAX) = '    new ' + @PocoName + ' { ';
    DECLARE @ColName NVARCHAR(128), @DataType NVARCHAR(128), @Value NVARCHAR(MAX);

    DECLARE col_cursor CURSOR FOR SELECT ColumnName, DataType FROM @Columns;
    OPEN col_cursor;

    FETCH NEXT FROM col_cursor INTO @ColName, @DataType;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @ValueSQL NVARCHAR(MAX) = '
        SELECT @ValueOut = CAST([' + @ColName + '] AS NVARCHAR(MAX))
        FROM #TempResults WHERE RowNum = ' + CAST(@i AS NVARCHAR);

        EXEC sp_executesql @ValueSQL, N'@ValueOut NVARCHAR(MAX) OUTPUT', @ValueOut = @Value OUTPUT;

        SET @RowText += @ColName + ' = ' +
            CASE 
                WHEN @Value IS NULL THEN 'null'
                WHEN @DataType IN ('char','nchar','varchar','nvarchar','text','ntext') THEN '''' + REPLACE(@Value, '''', '''''') + ''''
                WHEN @DataType = 'bit' THEN CASE WHEN @Value = '1' THEN 'true' ELSE 'false' END
                WHEN @DataType = 'uniqueidentifier' THEN 'Guid.Parse(''' + @Value + ''')'
                WHEN @DataType IN ('date','datetime','datetime2','smalldatetime') THEN 'DateTime.Parse(''' + @Value + ''')'
                ELSE @Value
            END + ', ';

        FETCH NEXT FROM col_cursor INTO @ColName, @DataType;
    END

    CLOSE col_cursor;
    DEALLOCATE col_cursor;

    SET @RowText = LEFT(@RowText, LEN(@RowText) - 2) + ' },' + CHAR(13) + CHAR(10);
    SET @SQL += @RowText;

    SET @i += 1;
END

-- Finalize output
SET @SQL = LEFT(@SQL, LEN(@SQL) - 3) + CHAR(13) + CHAR(10) + '};';

-- Output result
PRINT @SQL;

-- Cleanup
go
DROP TABLE #TempResults;
