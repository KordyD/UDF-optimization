# Оптимизация функции (UDF) возврата списка заказов

Задание к курсу Оптимизация БД

## Порядок выполнения и взаимодействия

1. Все вопросы оформлять в виде Issue
2. Все изменения и результаты оформлять в виде Pull Request из собственного fork

## Описание

В репозитории находится скрипт для создания объектов БД (MS SQL Server).
Описание таблиц:

- `Works` - заказы на проведение исследований
- `WorkItem` - элементы заказа (заказанное исследование)
- `Analiz` - спецификации исследования
- `Employee` - сотрудники
  Остальные таблицы для выполнения задания значения не имеют.

Для получения списка заказов с заранее настроенным количеством, со стороны клиентского приложения направляется запрос:

`select top 3000 * from dbo.F_WORKS_LIST()`

## Требования к окружению

MS SQL Server любой версии (допустимо использовать MS SQL Server for Linux или Windows).
Допустимо использование иной СУБД при портировании исходного скрипта с учётом конечного диалекта SQL.

## Начальные действия

1. Ознакомиться со скриптом создания базы данных
2. Ознакомиться с программными компонентами (функции)
3. Разработать и применить генератор тестовых данных

Ожидаемый результат - доступная для оптимизации БД с тестовыми данными

## Проблема

Пользователи приложения пользуются на низкую производительность при загрузке списка, при этом отсутствуют возможности отладить приложение и внести в него правки.

## Задача 1-го уровня

Проанализировать скрипт функции получения списка заказов и связанные с ней объекты, перечислить выявленные недочёты и потенциальные проблемы производительности.

### Основные проблемы и рекомендации

1. - Проблема: Многострочная табличная функция (MSTVF)
   - Описание: Не встраивается оптимизатором, приводит к лишним spool-операциям и медленным планам.
2. - Проблема: Частые вызовы скалярных UDF (RBAR)
   - Описание: Для каждой строки выполняются отдельные запросы (COUNT, получение ФИО), что сильно замедляет при росте числа записей.
3. - Проблема: Отсутствие ключевых индексов
   - Описание: Таблицы Works(Is_Del), WorkItem(Id_Work, Is_Complit) сканируются целиком, увеличивая I/O и время ответов.
4. - Проблема: Форматирование даты в функции
   - Описание: CONVERT(varchar, CREATE_Date, 104) превращает дату в строку, ломает использование индексов и фильтрацию на уровне БД.
5. - Проблема: ORDER BY внутри функции
   - Описание: В MSTVF без TOP сортировка игнорируется вызывающим запросом и лишь лишь создаёт лишние затраты на упорядочение.

**Время выполнения функции**

```
-- SQL Server Execution Times:
-- CPU time = 25612 ms, elapsed time = 25624 ms.
-- Total execution time: 00:00:25.638
```

## Задача 2-го уровня

Предложить правки запросов без модификации структуры БД такие, что время выполнения запроса получения `3 000` заказов из `50 000` со средним количеством элементов в заказе равным `3` не будет превышать `1-2` сек.
При выполнении задания допускается использовать LLM. В случае использования LLM должны быть приведены используемые промты на русском или английском языке.

### Рекомендации по оптимизации

1. Переписать в inline TVF:

```sql
CREATE FUNCTION dbo.F_WORKS_LIST_INLINE()
RETURNS TABLE
AS
RETURN
  SELECT
    w.Id_Work,
    w.Create_Date,
    w.MaterialNumber,
    w.Is_Complit,
    w.Fio,
    CONVERT(varchar(10), w.Create_Date, 104) AS D_Date,
    COUNT(CASE WHEN wi.Is_Complit = 0 … END) OVER(PARTITION BY w.Id_Work) AS WorkItemsNotComplit,
    …
    CASE WHEN … END AS Is_Print
  FROM dbo.Works AS w
  LEFT JOIN dbo.WorkStatus s ON w.StatusId = s.StatusID
  LEFT JOIN dbo.WorkItem wi ON wi.Id_Work = w.Id_Work AND wi.Id_Analiz NOT IN (…)
  …
  WHERE w.Is_Del <> 1;
```

2. Объединить подсчёты через агрегаты/OVER() вместо скалярных вызовов.
3. Добавить недостающие индексы:

```sql
CREATE INDEX IX_WorkItem_ByWork_Complit ON dbo.WorkItem (Id_Work, Is_Complit);
CREATE INDEX IX_Works_IsDel_IdWork ON dbo.Works (Is_Del, Id_Work DESC);
```

4. Удалить ненужный ORDER BY внутри функции и при необходимости сортировать уже в запросе-потребителе.
5. Вынести форматирование дат и объединение ФИО из UDF на уровень клиента/приложения или создать view с нужным представлением.

**Результат**

```
-- SQL Server Execution Times:
-- CPU time = 96 ms, elapsed time = 104 ms.
-- Total execution time: 00:00:00.158
```

## Задача 3-го уровня

Если для оптимизации требуется создание новых таблиц, столбцов, триггеров или хранимых процедур (функций), то необходимо описать возможные недостатки и отрицательные последствия от таких изменений.

### Примеры дополнительных структур

1. Вспомогательная агрегированная таблица

```sql
-- Таблица для хранения числа неоконченных и завершённых позиций по каждому заказу

CREATE TABLE dbo.WorksSummary (
Id_Work INT NOT NULL PRIMARY KEY,
NotComplete INT NOT NULL,
Complete INT NOT NULL,
LastUpdated DATETIME NOT NULL
);

-- Процедура для полной пересборки (например, раз в ночь)
CREATE PROCEDURE dbo.RebuildWorksSummary
AS
BEGIN
TRUNCATE TABLE dbo.WorksSummary;

    INSERT INTO dbo.WorksSummary (Id_Work, NotComplete, Complete, LastUpdated)
    SELECT
        wi.Id_Work,
        SUM(CASE WHEN wi.Is_Complit = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN wi.Is_Complit = 1 THEN 1 ELSE 0 END),
        GETDATE()
    FROM dbo.WorkItem wi
    WHERE wi.Id_Analiz NOT IN (SELECT Id_Analiz FROM dbo.Analiz WHERE Is_Group = 1)
    GROUP BY wi.Id_Work;

END;
```

2. Денормализованный столбец

```sql
-- Добавляем в Works колонку с полным ФИО вместо JOIN по Employee

ALTER TABLE dbo.Works
ADD EmployeeFullName AS (Surname + ' ' + Name + COALESCE(' ' + Patronymic, '')) PERSISTED;
```

3. Триггер на DML

```sql
-- Триггер поддерживает WorksSummary «на лету»
CREATE TRIGGER dbo.tr_WorkItem_UpdateSummary
ON dbo.WorkItem
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
SET NOCOUNT ON;

    -- Вычисляем затронутые заказы
    DECLARE @works TABLE (Id_Work INT PRIMARY KEY);
    INSERT INTO @works (Id_Work)
    SELECT DISTINCT Id_Work FROM
    (
        SELECT Id_Work FROM inserted
        UNION
        SELECT Id_Work FROM deleted
    ) AS t;

    -- Обновляем для каждого заказа
    UPDATE ws
    SET
        NotComplete = s.NotComplete,
        Complete    = s.Complete,
        LastUpdated = GETDATE()
    FROM dbo.WorksSummary ws
    JOIN
    (
        SELECT
            wi.Id_Work,
            SUM(CASE WHEN wi.Is_Complit = 0 THEN 1 ELSE 0 END) AS NotComplete,
            SUM(CASE WHEN wi.Is_Complit = 1 THEN 1 ELSE 0 END) AS Complete
        FROM dbo.WorkItem wi
        WHERE wi.Id_Analiz NOT IN (SELECT Id_Analiz FROM dbo.Analiz WHERE Is_Group = 1)
          AND wi.Id_Work IN (SELECT Id_Work FROM @works)
        GROUP BY wi.Id_Work
    ) AS s ON ws.Id_Work = s.Id_Work;

END;
```

4. Хранимая процедура для выборки с кешем

```sql
-- Процедура читает из WorksSummary, если дата свежая, иначе пересобирает
CREATE PROCEDURE dbo.GetWorksWithSummary
AS
BEGIN
-- Если таблица не обновлялась за последний час, пересобираем
IF EXISTS (
SELECT 1 FROM dbo.WorksSummary
WHERE LastUpdated < DATEADD(HOUR, -1, GETDATE())
)
EXEC dbo.RebuildWorksSummary;

    SELECT
        w.Id_Work,
        w.Create_Date,
        w.MaterialNumber,
        w.Is_Complit,
        w.EmployeeFullName,
        ws.NotComplete,
        ws.Complete,
        s.StatusName
    FROM dbo.Works w
    LEFT JOIN dbo.WorksSummary ws ON w.Id_Work = ws.Id_Work
    LEFT JOIN dbo.WorkStatus s ON w.StatusId = s.StatusID
    WHERE w.Is_Del <> 1;

END;
```

5. Разбиение таблицы (partitioning)

```sql
-- Функция разбиения по году создания
CREATE PARTITION FUNCTION pf_WorkItem_ByYear (DATETIME)
AS RANGE RIGHT FOR VALUES
('2022-01-01','2023-01-01','2024-01-01');

-- Схема, маппящая все партиции в тот же filegroup (пример)
CREATE PARTITION SCHEME ps_WorkItem_ByYear
AS PARTITION pf_WorkItem_ByYear ALL TO ([PRIMARY]);

-- Переводим таблицу в партиционирование
CREATE TABLE dbo.WorkItem_P (
Id_WorkItem INT IDENTITY PRIMARY KEY,
Id_Work INT NOT NULL,
Is_Complit BIT NOT NULL,
Id_Analiz INT NOT NULL,
Create_Date DATETIME NOT NULL
) ON ps_WorkItem_ByYear(Create_Date);
```

### Вывод – общие минусы

- Рост сложности поддержки: добавляются скрытые слои логики (триггеры, процедуры, вспомогательные таблицы), что затрудняет отладку и обучение новых разработчиков.
- Риск рассинхронизации данных: дублирование (денормализация) и агрегирование требуют надёжной синхронизации, иначе отчёты/кэши устареют.
- Дополнительная нагрузка на DML: триггеры и синхронизационные процедуры увеличивают время INSERT/UPDATE/DELETE и могут стать «узким местом» при пиковых объёмах.
- Увеличение объёма хранимых данных: агрегации и денормализованные поля занимают дополнительное пространство и могут ухудшать компрессию.
- Административные затраты: миграции, управление партициями, настройка безопасности и резервного копирования усложняются и требуют участия DBA.

## Использованные промты

```
Составь генератор тестового датасета для MSSQL Server на основе созданных таблиц в файле Create objects.sql.
Создай 50000 заказов и в среднем по 3 WorkItem на заказ.
```

```
Проанализируй скрипт функции f_works_list и предложи решения потенциальных проблем производительности. Предложи оптимизированную функцию f_works_list_2, которая ускоряет выполнение запроса до 1–2 секунд при объёме 50000 заказов и 150000 WorkItem
```
