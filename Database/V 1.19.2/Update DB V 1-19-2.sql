/* 
	Updates de the KPIDB database to version 1.19.2
*/

Use [Master]
GO 

IF  NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'KPIDB')
	RAISERROR('KPIDB database Doesn´t exists. Create the database first',16,127)
GO

PRINT 'Updating KPIDB database to version 1.19.2'

Use [KPIDB]
GO
PRINT 'Verifying database version'

/*
 * Verify that we are using the right database version
 */

IF  NOT ((EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[usp_GetVersionMajor]') AND type in (N'P', N'PC'))) 
	AND 
	(EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[usp_GetVersionMinor]') AND type in (N'P', N'PC'))))
		RAISERROR('KPIDB database has not been initialized.  Cant find version stored procedures',16,127)


declare @smiMajor smallint 
declare @smiMinor smallint

exec [dbo].[usp_GetVersionMajor] @smiMajor output
exec [dbo].[usp_GetVersionMinor] @smiMinor output

IF NOT (@smiMajor = 1 AND @smiMinor = 19) 
BEGIN
	RAISERROR('KPIDB database is not in version 1.19 This program only applies to version 1.19',16,127)
	RETURN;
END

PRINT 'KPIDB Database version OK'
GO

USE [KPIDB]
GO

/****** Object:  StoredProcedure [dbo].[usp_ORG_GetOrganizationListForUser]    Script Date: 08/04/2016 10:47:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================================
-- Author:		Gabriela Sanchez V.
-- Create date: Jun 2 2016
-- Description:	Get List of Organizations that user has view rights to
-- =============================================================
ALTER PROCEDURE [dbo].[usp_ORG_GetOrganizationListForUser]
	-- Add the parameters for the stored procedure here
	@userName varchar(50)
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	--- Get list of KPIS where user has acccess.  In the sourceObjectType
	-- column we will record where we got this from, and the objectID will
	-- tell us the ID of the object where this KPI came from.
	DECLARE @orgList as TABLE(organizationID int, sourceObjectType varchar(100), objectID int)

	-- For the following description ORG = ORGANIZATION, ACT = ACTIVITY, PPL = PEOPLE, PROF = PROJECT. 
	--If we need to determine the list of KPIs that a specific user can see 
	--we need to follow the following steps:
	--
	--1. Search for all ORGs where the user has OWN permissions and add to the list 
	--   of organizations to those ORGs.
	--2. Search for all ORGs where the user has MAN_KPI permissions or ORG has public 
	--   MAN_KPI and add to the list of ORGs all of these that are directly associated 
	--   to the organization
	--3. Search for all ORGs where the user has MAN_PROJECT permissions or ORG has public 
	--   MAN_PROJECT, then search for all PROJs then add to the ORG list all of the ORGs 
	--   that are associated to these PROJs.
	--4. Search for all ORGs where the user has MAN_ACTITIVIES permissions or ORG has public 
	--   MAN_ACTITIVIES and search for ACT that are associated to these ORGs and ARE NOT 
	--   associated to any PROJ, then add to the ORG list all of the ORGs that are 
	--   associated to these ACT.
	--5. Search for all ORGs where the user has MAN_PEOPLE permissions or where the ORG has 
	--   public MAN_PEOPLE, then search for all of the PPL that are associated to those 
	--   ORGs and finally add to the ORG list all of the ORGs that are associated to those 
	--   PPL.
	--6. Search for all ACT where the user has OWN or MAN_KPI permissions or the ACT is public 
	--   MAN_KPI and add to the ORG list all of the ORGs that are associated to the ACT.
	--7. Search for all PROJ where the user has OWN or MAN_KPI permissions, or where the PROJ 
	--   is public MAN_KPI and add to the ORG list all of the ORGs that are associated to those
	--   PROJ.
	--8. Search for all PROJ where the user has MAN_ACTIVITIES permissions or where the PROJ is 
	--   public MAN_ACTIVITIES, then search for all of the ACT that are associated to these 
	--   PROJs and finally add to the ORG list the ORGs that are associated to these ACT.
	--9. Search for all PPL where the user has OWN or MAN_KPI permissions or where the PPL is 
	--    public MAN_KPI and add to the ORG list all of the ORGs that are associated to these PPL.
	--10. Add to the ORG list all of the KPIs that are public VIEW_KPI
	--11.	Add to the ORG list all of the ORGs where the user has OWN or VIEW_KPI or ENTER_DATA
	--      permissions.
	--
	--At the end of this, we should have a list of all of the ORGs that the user can see.

	-- So lets start with step 1.
 
	--1. Search for all ORGs where the user has OWN permissions and add to the list 
	--   of organizations to those ORGs.

	insert into @orgList
	select [organizationID], 'ORG OWN (1)', [organizationID] 
	from [dbo].[tbl_Organization]
	where [deleted] = 0
	  and [organizationID] in (
								select [objectID]
								from [dbo].[tbl_SEG_ObjectPermissions]
								where [objectTypeID] = 'ORGANIZATION' and objectActionID = 'OWN'
								and username = @userName
							)

	--2. Search for all ORGs where the user has MAN_KPI permissions or ORG has public 
	--   MAN_KPI and add to the list of ORGs all of these that are directly associated 
	--   to the organization

	insert into @orgList
	select [organizationID], 'ORG MAN_ORG (2)', [organizationID] 
	from [dbo].[tbl_Organization]
	where [deleted] = 0
	  and [organizationID] in (
							SELECT [objectID] 
							FROM [dbo].[tbl_SEG_ObjectPermissions]
							WHERE [objectTypeID] = 'ORGANIZATION' and objectActionID = 'MAN_KPI' AND username = @userName
							UNION
							SELECT [objectID]
							FROM [dbo].[tbl_SEG_ObjectPublic]
							WHERE [objectTypeID] = 'ORGANIZATION' and objectActionID = 'MAN_KPI'
						) 

	--3. Search for all ORGs where the user has MAN_PROJECT permissions or ORG has public 
	--   MAN_PROJECT, then search for all PROJs then add to the ORG list all of the ORGs 
	--   that are associated to these PROJs.

	insert into @orgList
	select [o].[organizationID], 'ORG MAN_PROJECT (3)', [p].[organizationID] 
	from [dbo].[tbl_Organization] [o]
	left join [dbo].[tbl_Project] [p] ON [p].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and ISNULL([p].[deleted],0) = 0
	  and [o].[organizationID] in (
		SELECT [objectID] 
		FROM [dbo].[tbl_SEG_ObjectPermissions]
		WHERE [objectTypeID] = 'ORGANIZATION' and objectActionID = 'MAN_PROJECT' AND username = @userName
		UNION
		SELECT [objectID]
		FROM [dbo].[tbl_SEG_ObjectPublic]
		WHERE [objectTypeID] = 'ORGANIZATION' and objectActionID = 'MAN_PROJECT'
	)
	
	--4. Search for all ORGs where the user has MAN_ACTITIVIES permissions or ORG has public 
	--   MAN_ACTITIVIES and search for ACT that are associated to these ORGs and ARE NOT 
	--   associated to any PROJ, then add to the ORG list all of the ORGs that are 
	--   associated to these ACT.
	
	insert into @orgList
	select [o].[organizationID], 'ORG MAN_ACTIVITY (4)', [o].[organizationID] 
	from [dbo].[tbl_Organization] [o] 
	left join [dbo].[tbl_Activity] [a] ON [a].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and ISNULL([a].[deleted],0) = 0
	  and [o].[organizationID] in (
							SELECT [objectID] 
							FROM [dbo].[tbl_SEG_ObjectPermissions]
							WHERE [objectTypeID] = 'ORGANIZATION' and objectActionID = 'MAN_ACTIVITY' AND username = @userName
							UNION
							SELECT [objectID]
							FROM [dbo].[tbl_SEG_ObjectPublic]
							WHERE [objectTypeID] = 'ORGANIZATION' and objectActionID = 'MAN_ACTIVITY'
						)  
      and [a].[projectID] is null

	--5. Search for all ORGs where the user has MAN_PEOPLE permissions or where the ORG has 
	--   public MAN_PEOPLE, then search for all of the PPL that are associated to those 
	--   ORGs and finally add to the ORG list all of the ORGs that are associated to those 
	--   PPL.

	insert into @orgList
	select [o].[organizationID], 'ORG MAN_PEOPLE (5)', [o].[organizationID] 
	from [dbo].[tbl_Organization] [o]
	left join [dbo].[tbl_People][p] ON [p].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and ISNULL([p].[deleted],0) = 0
	  and [o].[organizationID] in (
									SELECT [objectID] 
									FROM [dbo].[tbl_SEG_ObjectPermissions]
									WHERE [objectTypeID] = 'ORGANIZATION' and objectActionID = 'MAN_PEOPLE' AND username = @userName
									UNION
									SELECT [objectID]
									FROM [dbo].[tbl_SEG_ObjectPublic]
									WHERE [objectTypeID] = 'ORGANIZATION' and objectActionID = 'MAN_PEOPLE'
								) 

	--6. Search for all ACT where the user has OWN or MAN_KPI permissions or the ACT is public 
	--   MAN_KPI and add to the ORG list all of the ORGs that are associated to the ACT.

	insert into @orgList
	select [a].[organizationID], 'ACT OWN (6)', [a].[activityID]
	from [dbo].[tbl_Activity][a]
	inner join [dbo].[tbl_Organization] [o] ON [a].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and [a].[deleted] = 0
	  and [a].[activityID] in (
							select [objectID]
							from [dbo].[tbl_SEG_ObjectPermissions]
							where [objectTypeID] = 'ACTIVITY' and objectActionID = 'OWN' and username = @userName
						) 

	insert into @orgList
	select [a].[organizationID], 'ACT-MAN_KPI (6)', [activityID] 
	FROM [dbo].[tbl_Activity][a]
	inner join [dbo].[tbl_Organization] [o] ON [a].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and [a].[deleted] = 0
	  and [a].[activityID] in (
							SELECT [objectID] 
							FROM [dbo].[tbl_SEG_ObjectPermissions]
							WHERE [objectTypeID] = 'ACTIVITY' and objectActionID = 'MAN_KPI' AND username = @userName
							UNION
							SELECT [objectID]
							FROM [dbo].[tbl_SEG_ObjectPublic]
							WHERE [objectTypeID] = 'ACTIVITY' and objectActionID = 'MAN_KPI'
						)

	--7. Search for all PROJ where the user has OWN or MAN_KPI permissions, or where the PROJ 
	--   is public MAN_KPI and add to the ORG list all of the ORGs that are associated to those
	--   PROJ.

	insert into @orgList
	select [p].[organizationID], 'PROJ OWN (7)', [projectID] 
	from [dbo].[tbl_Project] [p]
	inner join [dbo].[tbl_Organization] [o] ON [p].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and [p].[deleted] = 0
	  and [p].[projectID] in (
							select [objectID]
							from [dbo].[tbl_SEG_ObjectPermissions]
							where [objectTypeID] = 'PROJECT' and objectActionID = 'OWN' and username = @userName
						)

	insert into @orgList
	select [p].[organizationID], 'PROJ-MAN_KPI (7)', [projectID] 
	FROM [dbo].[tbl_Project] [p]
	inner join [dbo].[tbl_Organization] [o] ON [p].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and [p].[deleted] = 0
	  and [p].[projectID] in (
							SELECT [objectID] 
							FROM [dbo].[tbl_SEG_ObjectPermissions]
							WHERE [objectTypeID] = 'PROJECT' and objectActionID = 'MAN_KPI' AND username = @userName
							UNION
							SELECT [objectID]
							FROM [dbo].[tbl_SEG_ObjectPublic]
							WHERE [objectTypeID] = 'PROJECT' and objectActionID = 'MAN_KPI'
						)

	--8. Search for all PROJ where the user has MAN_ACTIVITIES permissions or where the PROJ is 
	--   public MAN_ACTIVITIES, then search for all of the ACT that are associated to these 
	--   PROJs and finally add to the ORG list the ORGs that are associated to these ACT.

	insert into @orgList
	select [a].[organizationID], 'PROJ-MAN_ACTIVITY (8)', [projectID] 
	from [dbo].[tbl_Activity] [a]
	inner join [dbo].[tbl_Organization] [o] ON [a].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and [a].[deleted] = 0
	  and [a].[projectID] in (
		SELECT [objectID] 
		FROM [dbo].[tbl_SEG_ObjectPermissions]
		WHERE [objectTypeID] = 'PROJECT' and objectActionID = 'MAN_ACTIVITY' AND username = @userName
		UNION
		SELECT [objectID]
		FROM [dbo].[tbl_SEG_ObjectPublic]
		WHERE [objectTypeID] = 'PROJECT' and objectActionID = 'MAN_ACTIVITY'
	)

	--9. Search for all PPL where the user has OWN or MAN_KPI permissions or where the PPL is 
	--    public MAN_KPI and add to the ORG list all of the ORGs that are associated to these PPL.

	insert into @orgList
	select [p].[organizationID], 'PPL OWN (9)', [personID]
	from [dbo].[tbl_People] [p]
	inner join [dbo].[tbl_Organization] [o] ON [p].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and [p].[deleted] = 0
	  and [p].[personID] in (
							select [objectID]
							from [dbo].[tbl_SEG_ObjectPermissions]
							where [objectTypeID] = 'PERSON' and objectActionID = 'OWN' and username = @userName
						)

	insert into @orgList
	select [p].[organizationID], 'PPL-MAN_KPI (9)', [personID] 
	FROM [dbo].[tbl_People] [p]
	inner join [dbo].[tbl_Organization] [o] ON [p].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and [p].[deleted] = 0
	  and [p].[personID] in (
		SELECT [objectID] 
		FROM [dbo].[tbl_SEG_ObjectPermissions]
		WHERE [objectTypeID] = 'PERSON' and objectActionID = 'MAN_KPI' AND username = @userName
		UNION
		SELECT [objectID]
		FROM [dbo].[tbl_SEG_ObjectPublic]
		WHERE [objectTypeID] = 'PERSON' and objectActionID = 'MAN_KPI'
	)

	--10. Add to the ORG list all of the KPIs that are public VIEW_KPI

	insert into @orgList
	select [k].[organizationID], 'KPI-PUB VIEW (10)', [kpiID] 
	FROM [dbo].[tbl_KPI] [k]
	inner join [dbo].[tbl_Organization] [o] ON [k].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and [k].[deleted] = 0
	  and [k].[kpiID] in (
						SELECT [objectID]
						FROM [dbo].[tbl_SEG_ObjectPublic]
						WHERE [objectTypeID] = 'KPI' and objectActionID = 'VIEW_KPI'
					)

	--11.	Add to the ORG list all of the ORGs where the user has OWN or VIEW_KPI or ENTER_DATA
	--      permissions.
	insert into @orgList
	select [k].[organizationID], 'KPI-VIEW-OWN-ENTER (11)', [kpiID] 
	FROM [dbo].[tbl_KPI] [k]
	inner join [dbo].[tbl_Organization] [o] ON [k].[organizationID] = [o].[organizationID]
	where [o].[deleted] = 0
	  and [k].[deleted] = 0
	  and [k].[kpiID] in (
					SELECT [objectID] 
					FROM [dbo].[tbl_SEG_ObjectPermissions]
					WHERE [objectTypeID] = 'KPI' and objectActionID = 'OWN' AND username = @userName
					union
					SELECT [objectID] 
					FROM [dbo].[tbl_SEG_ObjectPermissions]
					WHERE [objectTypeID] = 'KPI' and objectActionID = 'ENTER_DATA' AND username = @userName
					union
					SELECT [objectID] 
					FROM [dbo].[tbl_SEG_ObjectPermissions]
					WHERE [objectTypeID] = 'KPI' and objectActionID = 'VIEW_KPI' AND username = @userName
				)

	select distinct organizationID from @orgList 


END
GO

--=================================================================================================
/****** Object:  StoredProcedure [dbo].[usp_KPI_GetKPITargetTimeFromKpi]    Script Date: 08/04/2016 13:33:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Gabriela Sanchez V.
-- Create date: 24/05/2016
-- Description:	Get KPI Target Time From KPI
-- =============================================
ALTER PROCEDURE [dbo].[usp_KPI_GetKPITargetTimeFromKpi]
	@kpiID INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @valor AS DECIMAL(21,9)
	DECLARE @targetID AS INT

	SELECT @targetID = [targetID],
	       @valor = [target]
	FROM [dbo].[tbl_KPITarget]
	WHERE [kpiID] = @kpiID
	
	DECLARE @year INT = 0
	DECLARE @month INT = 0
	DECLARE @day INT = 0
	DECLARE @hour INT = 0
	DECLARE @minute INT = 0

	DECLARE @fechaBase AS DATETIME
	DECLARE @fechaObtenida DATETIME
	
	IF (ISNULL(@valor,0) > 0)
	BEGIN
		
		SET @fechaBase = '1900-01-01'	
		SET @fechaObtenida = CAST(@valor AS DATETIME)
		--REDONDEO AL SEGUNDO
		SET @fechaObtenida = dateadd(second, round(datepart(second,@fechaObtenida)*2,-1) / 2-datepart(second,@fechaObtenida), @fechaObtenida)

		SET @year = DATEDIFF(YY,@fechaBase,@fechaObtenida)
		SET @fechaObtenida = DATEADD(YY,-@year,@fechaObtenida)

		SET @month = DATEDIFF(MM,@fechaBase,@fechaObtenida) 
		SET @fechaObtenida = DATEADD(MM,-@month,@fechaObtenida)

		SET @day = DATEDIFF(DD,@fechaBase,@fechaObtenida) 
		SET @fechaObtenida = DATEADD(DD,-@day,@fechaObtenida)

		SET @hour = DATEDIFF(HH,@fechaBase,@fechaObtenida) 
		SET @fechaObtenida = DATEADD(HH,-@hour,@fechaObtenida)

		SET @minute = DATEDIFF(MINUTE,@fechaBase,@fechaObtenida) 

	END
	
	SELECT @kpiID as kpiID,
	       ISNULL(@targetID,0) as targetID,
	       @year as [year],
	       @month as [month],
	       @day as [day],
	       @hour as [hour],
	       @minute as [minute]

END
GO

--=================================================================================================

/*
 * We are done, mark the database as a 1.19.2 database.
 */
DELETE FROM [dbo].[tbl_DatabaseInfo] 
INSERT INTO [dbo].[tbl_DatabaseInfo] 
	([majorversion], [minorversion], [releaseversion])
	VALUES (1,19,2)
GO