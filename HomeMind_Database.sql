-- =====================================================================
--  HOMEmind database  (SQL Server)
--  Run the file in parts, in this order:
--   1) create database + tables   2) insert data   3) queries / views / procedures
--  Every "go" line separates a batch (create view / create procedure must start a batch).
-- =====================================================================

create database HomeMind;
go


-- =====================================================================
--  PART 1: TABLES
-- =====================================================================

-- ---------- Lookup tables (the admin manages them) ----------

create table SubscriptionPlans (
PlanID int primary key,
PlanName VARCHAR(50) not null unique
);

create table Brands (
BrandID int primary key,
BrandName VARCHAR(80) not null unique
);

create table ServiceCategories (
CategoryID int primary key,
CategoryName VARCHAR(80) not null unique
);

create table DeviceTypes (
DeviceTypeID int primary key,
TypeName VARCHAR(80) not null unique,
CategoryID INT foreign key references ServiceCategories(CategoryID)
);

-- ---------- Accounts: everyone who signs in ----------
-- AccountType: user / technician / company / service_center / admin

create table Accounts (
AccountID int primary key,
AccountType VARCHAR(20) not null,
Email VARCHAR(256) not null unique,
PasswordHash VARCHAR(255) not null,
FullName NVARCHAR(150) not null,
Phone VARCHAR(30),
City NVARCHAR(80),
Address NVARCHAR(250),
Status VARCHAR(12) default 'active',
CreatedAt DATETIME default GETDATE()
);

create table Companies (
CompanyID int primary key,
AccountID INT not null unique foreign key references Accounts(AccountID),
CompanyName NVARCHAR(150) not null,
Industry NVARCHAR(60),
CommercialRegNo VARCHAR(40),
TaxNumber VARCHAR(40),
Email VARCHAR(256),
Phone VARCHAR(30),
City NVARCHAR(80),
Address NVARCHAR(250),
ContactName NVARCHAR(150),
ContactRole NVARCHAR(80),
ContactEmail VARCHAR(256),
ContactPhone VARCHAR(30),
About NVARCHAR(500),
PlanID INT foreign key references SubscriptionPlans(PlanID),
BillingCycle VARCHAR(8) default 'monthly',
ApprovalLimitJOD DECIMAL(10,2) default 100,   -- estimates above this need manager approval
ApproverEmail VARCHAR(256),
IsVerified BIT default 0
);

-- TechnicianType: independent / authorized (brand service center) / in_house (works for a company)
create table Technicians (
TechnicianID int primary key,
AccountID INT not null unique foreign key references Accounts(AccountID),
TechnicianType VARCHAR(12) not null,
CompanyID INT foreign key references Companies(CompanyID),
ServiceCenterName NVARCHAR(150),
AuthorizationNumber VARCHAR(60),
CenterAddress NVARCHAR(250),
ServiceArea NVARCHAR(120),
YearsExperience INT,
Availability VARCHAR(10) default 'available',
Bio NVARCHAR(500),
IsVerified BIT default 0
);

-- External providers (independent technicians and authorized centers) subscribe to use HOMEmind.
create table ProviderSubscriptionPlans (
ProviderPlanID int primary key,
ProviderType VARCHAR(12) not null check (ProviderType in ('independent','authorized')),
PlanName NVARCHAR(80) not null,
Description NVARCHAR(300),
PriceJOD DECIMAL(10,2) null,
TrialDays INT not null default 0,
IsActive BIT default 1
);

create table ProviderSubscriptions (   -- a provider can use HomeMind only while Status = 'active' and EndDate has not passed (no grace period)
ProviderSubscriptionID int primary key,
TechnicianID INT not null foreign key references Technicians(TechnicianID),
ProviderPlanID INT not null foreign key references ProviderSubscriptionPlans(ProviderPlanID),
Status VARCHAR(12) default 'pending' check (Status in ('pending','active','expired','cancelled')),
StartDate DATE,
EndDate DATE,
IsTrial BIT not null default 0,
CreatedAt DATETIME default GETDATE(),
check (EndDate is null or StartDate is null or EndDate >= StartDate)
);

create table ProviderSubscriptionPayments (
ProviderSubscriptionPaymentID int primary key,
ProviderSubscriptionID INT not null foreign key references ProviderSubscriptions(ProviderSubscriptionID),
AmountJOD DECIMAL(10,2) not null check (AmountJOD > 0),
PaymentReference NVARCHAR(200) not null unique,
PaidAt DATETIME not null default GETDATE(),
PeriodStart DATE not null,
PeriodEnd DATE not null,
check (PeriodEnd >= PeriodStart)
);

-- Brands that an authorized center services (many to many, like StudentCourses)
create table TechnicianBrands (
TechnicianID INT foreign key references Technicians(TechnicianID),
BrandID INT foreign key references Brands(BrandID),
Primary Key(TechnicianID, BrandID)
);

-- Work categories a technician is good at (many to many)
create table TechnicianCategories (
TechnicianID INT foreign key references Technicians(TechnicianID),
CategoryID INT foreign key references ServiceCategories(CategoryID),
Primary Key(TechnicianID, CategoryID)
);

-- ---------- Locations and devices ----------

create table Locations (
LocationID int primary key,
CompanyID INT foreign key references Companies(CompanyID),
LocationName NVARCHAR(120) not null,
Address NVARCHAR(250),
City NVARCHAR(80)
);

create table Devices (
DeviceID int primary key,
OwnerAccountID INT not null foreign key references Accounts(AccountID),
CompanyID INT foreign key references Companies(CompanyID),
LocationID INT foreign key references Locations(LocationID),
RoomLabel NVARCHAR(80),
DeviceName NVARCHAR(120) not null,
DeviceTypeID INT foreign key references DeviceTypes(DeviceTypeID),
CategoryID INT not null foreign key references ServiceCategories(CategoryID),
BrandID INT foreign key references Brands(BrandID),
Model VARCHAR(80),
SerialNumber VARCHAR(80),
PurchaseDate DATE,
PurchasePrice DECIMAL(10,2),
LastServiceDate DATE,
MaintenanceIntervalMonths INT,
PurchaseProofUrl NVARCHAR(300)   -- invoice or warranty card, used by centers to confirm coverage
);

create table Warranties (
WarrantyID int primary key,
DeviceID INT not null foreign key references Devices(DeviceID),
StartDate DATE,
EndDate DATE not null,
CoverageNotes NVARCHAR(500)
);

-- ---------- Service requests ----------
-- Status codes (identical to js/request-status.js):
-- new > matching (the technician you chose must accept) > accepted > estimate_sent > estimate_approved > in_progress > completed > payment_reported > paid > rated
-- warranty route: new > center_review > center_assigned > in_progress > completed > rated   (no estimate, no payment)
-- side states: no_provider_found, unable_to_resolve, estimate_rejected, waiting_parts, cancelled, problem_reported

create table ServiceRequests (
RequestID int primary key,
DeviceID INT not null foreign key references Devices(DeviceID),
RequesterAccountID INT not null foreign key references Accounts(AccountID),
ServiceType NVARCHAR(50) not null,
Description NVARCHAR(1000),
Urgency VARCHAR(10) default 'normal',
WarrantyActiveAtRequest BIT not null,
Status VARCHAR(30) not null default 'new' check (Status in ('new','matching','no_provider_found','center_review','center_assigned','unable_to_resolve','accepted','estimate_sent','estimate_approved','estimate_rejected','in_progress','waiting_parts','completed','payment_reported','paid','rated','cancelled','problem_reported')),
Address NVARCHAR(250),
PreferredDate DATE,
PreferredTime VARCHAR(20),
CostCenterRef NVARCHAR(60),        -- company cost center / PO reference
CancelReason NVARCHAR(300),
CreatedAt DATETIME default GETDATE(),
CompletedAt DATETIME               -- starts the 14-day "report a problem" window
);

-- Every try to fix the same request: authorized center first, then (if the user approves) an independent technician
-- ProviderKind: authorized / independent / in_house
-- Status: pending (an offer, answer before RespondBy) / accepted / in_progress / completed / declined / expired / unresolved
-- An independent technician has 10 minutes to answer, an authorized center 4 hours.
create table ServiceAttempts (
AttemptID int primary key,
RequestID INT not null foreign key references ServiceRequests(RequestID),
AttemptNo INT not null,
TechnicianID INT not null foreign key references Technicians(TechnicianID),
ProviderKind VARCHAR(12) not null,
Status VARCHAR(15) default 'pending' check (Status in ('pending','accepted','in_progress','completed','declined','expired','unresolved')),
UnresolvedReason NVARCHAR(1000),
UserApprovedTransfer BIT default 0,
AssignedAt DATETIME default GETDATE(),
FinishedAt DATETIME,
RespondBy DATETIME,                 -- deadline for the provider to answer
DeclineReason NVARCHAR(200),
CoverageDecision VARCHAR(12) check (CoverageDecision in ('covered','not_covered','cannot_fix'))   -- authorized centers only
);

-- The estimate comes first. Independent technicians cannot start before it is approved.
-- The final invoice may be at most 10% above the approved estimate (checked in usp_CompleteIndependentService).
create table ServiceEstimates (
EstimateID int primary key,
AttemptID INT not null foreign key references ServiceAttempts(AttemptID),
Diagnosis NVARCHAR(500) not null,
PlannedWork NVARCHAR(1000),
PartsCost DECIMAL(10,2) not null default 0,
LaborCost DECIMAL(10,2) not null default 0,
OtherCost DECIMAL(10,2) not null default 0,
EstimatedTotal AS (PartsCost + LaborCost + OtherCost),
PlannedDate DATE,
Status VARCHAR(10) not null default 'sent' check (Status in ('sent','approved','rejected','expired','revised')),
SentAt DATETIME default GETDATE(),
ValidUntil DATETIME,                -- SentAt + 48 hours
DecidedAt DATETIME,
RejectReason NVARCHAR(200),
NeedsManagerApproval BIT default 0, -- company estimate above Companies.ApprovalLimitJOD
ManagerApprovedAt DATETIME
);

create table ServiceReports (
ReportID int primary key,
AttemptID INT not null unique foreign key references ServiceAttempts(AttemptID),
EstimateID INT foreign key references ServiceEstimates(EstimateID),
FaultFound NVARCHAR(500),
WorkDescription NVARCHAR(2000),
PartsReplaced NVARCHAR(500),
FinalAmount DECIMAL(10,2) null,        -- NULL for authorized centers and in_house staff
InvoiceNotes NVARCHAR(500),
CustomerConfirmedAt DATETIME,          -- the customer confirmed the work is done
PaymentStatus VARCHAR(15) not null default 'unpaid'
    CHECK (PaymentStatus in ('not_required','unpaid','reported','paid'))
);

-- HOMEmind never holds the money and takes no commission: the customer pays the independent technician directly.
-- The customer reports the payment, then the technician confirms receiving it.
create table Payments (
PaymentID int primary key,
ReportID INT not null unique foreign key references ServiceReports(ReportID),
Method VARCHAR(5) not null check (Method in ('cash','cliq')),
Amount DECIMAL(10,2) not null,
Status VARCHAR(10) not null default 'reported' check (Status in ('reported','confirmed','disputed')),
ReportedAt DATETIME default GETDATE(),
ConfirmedAt DATETIME
);

create table Reviews (
ReviewID int primary key,
AttemptID INT not null unique foreign key references ServiceAttempts(AttemptID),
TechnicianID INT not null foreign key references Technicians(TechnicianID),
ReviewerAccountID INT not null foreign key references Accounts(AccountID),
Rating INT not null,
Comment NVARCHAR(1000),
CreatedAt DATETIME default GETDATE()
);



-- ---------- AI assistant, notifications, security ----------

-- After the service: the customer can report a problem for 14 days after CompletedAt (free, same request)
create table ProblemReports (
ProblemID int primary key,
RequestID INT not null foreign key references ServiceRequests(RequestID),
ReportedByAccountID INT not null foreign key references Accounts(AccountID),
ProblemType NVARCHAR(80) not null,
Details NVARCHAR(1000) not null,
Status VARCHAR(10) not null default 'open' check (Status in ('open','resolved','rejected')),
CreatedAt DATETIME default GETDATE(),
ResolvedAt DATETIME,
ResolutionNote NVARCHAR(500)
);

-- Every status change of a request (filled by trg_ServiceRequests_StatusHistory)
create table RequestStatusHistory (
HistoryID int primary key,
RequestID INT not null foreign key references ServiceRequests(RequestID),
OldStatus VARCHAR(30),
NewStatus VARCHAR(30) not null,
ChangedAt DATETIME default GETDATE()
);

-- One AiSessions row = one conversation; every turn (user and assistant) is a row in AiMessages.
create table AiSessions (
SessionID int primary key,
AccountID INT not null foreign key references Accounts(AccountID),
DeviceID INT foreign key references Devices(DeviceID),
StartedAt DATETIME default GETDATE()
);

create table AiMessages (
MessageID int primary key,
SessionID INT not null foreign key references AiSessions(SessionID),
Sender VARCHAR(9) not null,
Body NVARCHAR(MAX) not null,
CreatedAt DATETIME default GETDATE()
);

create table Notifications (
NotificationID int primary key,
AccountID INT not null foreign key references Accounts(AccountID),
Title NVARCHAR(150) not null,
Body NVARCHAR(500),
IsRead BIT default 0,
CreatedAt DATETIME default GETDATE()
);

create table PasswordResetTokens (
TokenID int primary key,
AccountID INT not null foreign key references Accounts(AccountID),
TokenHash VARCHAR(128) not null,
ExpiresAt DATETIME not null,
UsedAt DATETIME
);

create table AuditLog (
LogID int primary key,
AdminAccountID INT foreign key references Accounts(AccountID),
Action NVARCHAR(100) not null,
Details NVARCHAR(1000),
CreatedAt DATETIME default GETDATE()
);

-- Index on the columns the site searches by most (like IX_Students_Email)
create NonClustered index IX_Devices_Owner on Devices(OwnerAccountID);
create NonClustered index IX_Requests_Requester on ServiceRequests(RequesterAccountID);
create NonClustered index IX_Attempts_Request on ServiceAttempts(RequestID);


-- =====================================================================
--  PART 2: DATA
--  (PasswordHash values are placeholders. The real hash is made by the C# backend.)
-- =====================================================================

insert into SubscriptionPlans
values(1,'Starter'), (2,'Business'), (3,'Enterprise');

insert into ProviderSubscriptionPlans (ProviderPlanID, ProviderType, PlanName, Description, PriceJOD, TrialDays)
values
(1,'independent','Independent Technician','30-day free trial, then 20 JOD per month. No commission: the customer pays the technician directly.',20.00,30),
(2,'authorized','Authorized Agent','30-day free trial, then 30 JOD per month. Warranty repairs are free for the customer.',30.00,30);

insert into Brands
values(1,'LG'), (2,'Samsung'), (3,'Ariston'), (4,'Carrier'), (5,'Cummins'), (6,'Otis'), (7,'Grundfos'), (8,'Toyota');

insert into ServiceCategories
values(1,'Electrical'), (2,'Air Conditioning'), (3,'Water & Plumbing'), (4,'Smart Electronics'), (5,'Home Appliances'), (6,'Washing Machines');

insert into DeviceTypes
values(1,'Air Conditioner',2), (2,'Refrigerator',5), (3,'Washing Machine',6), (4,'Water Heater',1),
(5,'Television',4), (6,'Dishwasher',5), (7,'Oven',5), (8,'Other',5),
(9,'Microwave',5), (10,'Clothes Dryer',5), (11,'Deep Freezer',5), (12,'Heating Boiler',1), (13,'Water Pump',3);

-- Accounts: 1 admin, 2 user, 3 company, 4-7 LG/Samsung centers, 8-10 independent, 11-12 company technicians,
-- 13-15 more independent technicians, 16-17 Ariston centers
insert into Accounts (AccountID, AccountType, Email, PasswordHash, FullName, Phone, City, Address, Status)
values
(1,'admin','admin@homemind.com','HASH_CHANGE_ME','HOMEmind Admin','0655550100','Amman','Abdali, Amman','active'),
(2,'user','lina@example.com','HASH_CHANGE_ME','Lina Saleh','0791111111','Amman','Khalda, Amman','active'),
(3,'company','info@ammantowers.com','HASH_CHANGE_ME','Rami Haddad','0655550142','Amman','Abdali Boulevard, Amman','active'),
(4,'technician','lg1@homemind.com','HASH_CHANGE_ME','LG Amman Service','0792000001','Amman','Amman','active'),
(5,'technician','lg2@homemind.com','HASH_CHANGE_ME','LG Irbid Service','0792000002','Amman','Amman','active'),
(6,'technician','samsung1@homemind.com','HASH_CHANGE_ME','Samsung Amman Service','0792000003','Amman','Amman','active'),
(7,'technician','samsung2@homemind.com','HASH_CHANGE_ME','Samsung Zarqa Service','0792000004','Amman','Amman','active'),
(8,'technician','ahmed@homemind.com','HASH_CHANGE_ME','Ahmed','0793000001','Amman','Amman','active'),
(9,'technician','omar@homemind.com','HASH_CHANGE_ME','Omar','0793000002','Amman','Amman','active'),
(10,'technician','sami@homemind.com','HASH_CHANGE_ME','Sami','0793000003','Amman','Amman','active'),
(11,'technician','hala@ammantowers.com','HASH_CHANGE_ME','Hala Mansour','0794000001','Amman','Amman','active'),
(12,'technician','tareq@ammantowers.com','HASH_CHANGE_ME','Tareq Daoud','0794000002','Amman','Amman','active'),
(13,'technician','khaled@homemind.com','HASH_CHANGE_ME','Khaled','0793000004','Amman','Amman','active'),
(14,'technician','yazan@homemind.com','HASH_CHANGE_ME','Yazan','0793000005','Amman','Amman','active'),
(15,'technician','mahmoud@homemind.com','HASH_CHANGE_ME','Mahmoud','0793000006','Amman','Amman','active'),
(16,'technician','ariston1@homemind.com','HASH_CHANGE_ME','Ariston Amman Service','0792000005','Amman','Amman','active'),
(17,'technician','ariston2@homemind.com','HASH_CHANGE_ME','Ariston Irbid Service','0792000006','Amman','Amman','active');

insert into Companies (CompanyID, AccountID, CompanyName, Industry, CommercialRegNo, TaxNumber, Email, Phone, City, Address,
 ContactName, ContactRole, ContactEmail, ContactPhone, About, PlanID, BillingCycle, IsVerified)
values
(1,3,'Amman Towers Group','Property management','CR-204518','TX-77310294','info@ammantowers.com','0655550142','Amman',
 'Abdali Boulevard, Abdali, Amman','Rami Haddad','Facilities Manager','rami.haddad@ammantowers.com','0790001122',
 'Property management group running medical, residential, office and warehouse sites across Amman.',2,'monthly',1);

insert into Technicians (TechnicianID, AccountID, TechnicianType, CompanyID, ServiceCenterName, AuthorizationNumber,
 CenterAddress, ServiceArea, YearsExperience, Availability, Bio, IsVerified)
values
(1,4,'authorized',null,'LG Amman Service','LG-AUTH-001','Amman','Amman',10,'available','Authorized LG service center',1),
(2,5,'authorized',null,'LG Irbid Service','LG-AUTH-002','Amman','Amman',8,'available','Authorized LG service center',1),
(3,6,'authorized',null,'Samsung Amman Service','SAM-AUTH-001','Amman','Amman',12,'available','Authorized Samsung service center',1),
(4,7,'authorized',null,'Samsung Zarqa Service','SAM-AUTH-002','Amman','Amman',7,'available','Authorized Samsung service center',1),
(5,8,'independent',null,null,null,null,'Amman',9,'available','Washing machine specialist',1),
(6,9,'independent',null,null,null,null,'Amman',6,'available','Home appliances technician',1),
(7,10,'independent',null,null,null,null,'Amman',7,'available','Electrical appliances technician',1),
(8,11,'in_house',1,null,null,null,'Amman',5,'available','Air conditioning technician at Amman Towers',1),
(9,12,'in_house',1,null,null,null,'Amman',4,'available','Water and plumbing technician at Amman Towers',1),
(10,13,'independent',null,null,null,null,'Amman',8,'available','Air conditioning technician',1),
(11,14,'independent',null,null,null,null,'Amman',5,'available','Smart electronics technician',1),
(12,15,'independent',null,null,null,null,'Amman',10,'available','Water and plumbing technician',1),
(13,16,'authorized',null,'Ariston Amman Service','ARI-AUTH-001','Amman','Amman',9,'available','Authorized Ariston service center',1),
(14,17,'authorized',null,'Ariston Irbid Service','ARI-AUTH-002','Amman','Amman',6,'available','Authorized Ariston service center',1);

insert into TechnicianBrands
values(1,1), (2,1), (3,2), (4,2),
(13,3), (14,3);

insert into TechnicianCategories
values(1,5), (1,6), (2,5), (3,2), (3,6), (4,5), (5,6), (6,5), (6,1), (7,1), (7,6), (8,2), (9,3),
(10,2), (11,4), (12,3), (13,1), (14,1);

-- Approved independent technicians start one 30-day free trial after approval.
-- These are demo subscriptions; the ASP.NET backend should call usp_StartIndependentTechnicianTrial after real approval.
insert into ProviderSubscriptions (ProviderSubscriptionID, TechnicianID, ProviderPlanID, Status, StartDate, EndDate, IsTrial)
values
(1,5,1,'active',CAST(GETDATE() AS DATE),DATEADD(DAY,29,CAST(GETDATE() AS DATE)),1),
(2,6,1,'active',CAST(GETDATE() AS DATE),DATEADD(DAY,29,CAST(GETDATE() AS DATE)),1),
(3,7,1,'active',CAST(GETDATE() AS DATE),DATEADD(DAY,29,CAST(GETDATE() AS DATE)),1),
(4,10,1,'active',CAST(GETDATE() AS DATE),DATEADD(DAY,29,CAST(GETDATE() AS DATE)),1),
(5,11,1,'active',CAST(GETDATE() AS DATE),DATEADD(DAY,29,CAST(GETDATE() AS DATE)),1),
(6,12,1,'active',CAST(GETDATE() AS DATE),DATEADD(DAY,29,CAST(GETDATE() AS DATE)),1);

insert into Locations
values(1,1,'Al-Shifa Medical Wing','Al-Shifa Street','Amman'),
(2,1,'Sweifieh Residential','Sweifieh','Amman'),
(3,1,'Abdali Office Tower','Abdali','Amman'),
(4,1,'Sahab Warehouse','Sahab Industrial Area','Amman');

insert into Devices (DeviceID, OwnerAccountID, CompanyID, LocationID, RoomLabel, DeviceName, DeviceTypeID, CategoryID, BrandID,
 Model, SerialNumber, PurchaseDate, PurchasePrice, LastServiceDate, MaintenanceIntervalMonths)
values
(1,2,null,null,'Living Room','Air Conditioner',1,2,2,'AR12-X','SN-HOME-0001','2026-01-15',450.00,'2026-06-10',6),
(2,2,null,null,'Living Room','Television',5,4,2,'QN55','SN-HOME-0002','2026-09-01',600.00,null,null),
(3,2,null,null,'Master Bedroom','Air Conditioner',1,2,1,'S4-W12','SN-HOME-0003','2025-12-10',480.00,'2026-06-12',6),
(4,2,null,null,'Master Bedroom','Television',5,4,1,'OLED48','SN-HOME-0004','2026-07-20',380.00,null,null),
(5,2,null,null,'Kitchen','Refrigerator',2,5,1,'GR-B247','SN-HOME-0005','2025-11-24',800.00,null,null),
(6,2,null,null,'Kitchen','Dishwasher',6,5,2,'DW60','SN-HOME-0006','2026-06-02',420.00,null,12),
(7,2,null,null,'Kitchen','Oven (Built-in)',7,5,1,'WSED7','SN-HOME-0007','2025-08-12',350.00,null,null),
(8,2,null,null,'Kitchen','Microwave',9,5,2,'MS23','SN-HOME-0008','2025-02-01',90.00,null,null),
(9,2,null,null,'Laundry Room','Washing Machine',3,6,2,'WW90T','SN-HOME-0009','2026-03-20',520.00,null,12),
(10,2,null,null,'Laundry Room','Clothes Dryer',10,5,1,'RH90','SN-HOME-0010','2026-03-20',460.00,null,12),
(11,2,null,null,'Bathroom','Water Heater',4,1,3,'ABS-80','SN-HOME-0011','2024-09-10',180.00,'2026-06-20',12),
(12,2,null,null,'Store Room','Deep Freezer',11,5,2,'RZ32','SN-HOME-0012','2026-03-05',400.00,null,null),
(13,2,null,null,'Utility Room','Heating Boiler',12,1,3,'CLAS-24','SN-HOME-0013','2025-10-05',700.00,null,12),
(14,2,null,null,'Roof Water Tank','Water Pump',13,3,7,'MQ3-45','SN-HOME-0014','2024-01-08',150.00,null,null),
(15,3,1,1,null,'Chiller #2',null,2,4,'30XA','SN-CO-0015','2023-05-10',12000.00,'2026-08-01',3),
(16,3,1,1,null,'Medical Fridge',null,5,1,'LSR-200','SN-CO-0016','2025-02-01',3500.00,'2026-07-01',6),
(17,3,1,1,null,'Backup Generator',null,1,5,'C150D5','SN-CO-0017','2025-03-10',22000.00,'2026-09-10',6),
(18,3,1,2,null,'Water Pump P-3',null,3,7,'CR-15','SN-CO-0018','2023-03-12',1500.00,'2026-05-01',6),
(19,3,1,3,null,'Elevator Motor',null,1,6,'Gen2','SN-CO-0019','2025-01-20',18000.00,'2026-09-20',3),
(20,3,1,4,null,'Forklift Charger',null,1,8,'TC-48','SN-CO-0020','2023-04-05',2400.00,'2026-07-15',6);

insert into Warranties
values(1,1,'2026-01-15','2027-06-15','Parts and labor'),
(2,2,'2026-09-01','2028-09-01','Parts and labor'),
(3,3,'2025-12-10','2027-12-10','Parts and labor'),
(4,4,'2026-07-20','2027-07-20','Parts and labor'),
(5,5,'2025-11-24','2026-11-24','Compressor and parts'),
(6,6,'2026-06-02','2028-06-02','Parts and labor'),
(7,7,'2025-08-12','2027-08-12','Parts and labor'),
(8,8,'2025-02-01','2026-02-01','Parts and labor'),
(9,9,'2026-03-20','2028-03-20','Motor 3 years, parts 2 years'),
(10,10,'2026-03-20','2027-03-20','Parts and labor'),
(11,11,'2024-09-10','2026-09-10','Parts only'),
(12,12,'2026-03-05','2028-03-05','Parts and labor'),
(13,13,'2025-10-05','2027-10-05','Parts and labor'),
(14,14,'2024-01-08','2026-01-08','Parts and labor'),
(15,15,'2023-05-10','2026-05-10','Parts and labor'),
(16,16,'2025-02-01','2027-02-01','Parts and labor'),
(17,17,'2025-03-10','2027-03-10','Parts and labor'),
(18,18,'2023-03-12','2026-03-12','Parts and labor'),
(19,19,'2025-01-20','2027-01-20','Parts and labor'),
(20,20,'2023-04-05','2026-04-05','Parts and labor');

insert into ServiceRequests (RequestID, DeviceID, RequesterAccountID, ServiceType, Description, Urgency, WarrantyActiveAtRequest, Status)
values
(204,9,2,'Repair','Does not drain after the cycle','normal',1,'unable_to_resolve'),
(205,5,2,'Repair','Temperature is not stable','urgent',1,'in_progress'),
(206,11,2,'Repair','No hot water','normal',0,'rated'),
(207,17,3,'Maintenance','Scheduled generator test','normal',1,'center_review'),
(208,15,3,'Repair','No cooling','urgent',0,'in_progress');

insert into ServiceAttempts (AttemptID, RequestID, AttemptNo, TechnicianID, ProviderKind, Status, UnresolvedReason, UserApprovedTransfer)
values
(1,204,1,3,'authorized','unresolved','Drain pump damage is not covered and the part is unavailable',0),
(2,205,1,1,'authorized','in_progress',null,0),
(3,206,1,7,'independent','completed',null,0),
(4,208,1,8,'in_house','in_progress',null,0);

insert into ServiceEstimates (EstimateID, AttemptID, Diagnosis, PlannedWork, PartsCost, LaborCost, OtherCost, PlannedDate, Status, ValidUntil, DecidedAt)
values(1,3,'Heating element burnt','Replace the heating element and test the heater',25.00,20.00,0.00,'2026-09-27','approved','2026-09-27 12:00','2026-09-26 15:30');

insert into ServiceReports (ReportID, AttemptID, EstimateID, FaultFound, WorkDescription, PartsReplaced, FinalAmount, CustomerConfirmedAt, PaymentStatus)
values(1,3,1,'Heating element burnt','Replaced the heating element and tested the heater','Heating element',45.00,'2026-09-28 17:50','paid');

insert into Payments (PaymentID, ReportID, Method, Amount, Status, ReportedAt, ConfirmedAt)
values(1,1,'cash',45.00,'confirmed','2026-09-28 18:00','2026-09-28 18:10');

update ServiceRequests set CompletedAt='2026-09-28 17:45' where RequestID=206;

insert into Reviews (ReviewID, AttemptID, TechnicianID, ReviewerAccountID, Rating, Comment)
values(1,3,7,2,5,'Fast and clean work');


insert into AiSessions (SessionID, AccountID, DeviceID)
values(1,2,9);

insert into AiMessages (MessageID, SessionID, Sender, Body)
values(1,1,'user','My washing machine does not drain'),
(2,1,'assistant','Please check the drain filter and the hose for blockages, then run a spin cycle.');

insert into Notifications (NotificationID, AccountID, Title, Body)
values(1,2,'Warranty ending soon','The warranty of your LG refrigerator ends in 23 days.'),
(2,2,'Authorized center could not resolve the problem','Review the result of request 204 and choose whether to continue with an independent technician.');


-- =====================================================================
--  PART 3: QUERIES THE SITE NEEDS (run each one to see the result)
-- =====================================================================

select * from Devices;

-- Each device with its brand and warranty end date
select Devices.DeviceName, Brands.BrandName, Warranties.EndDate
from Devices
inner join Brands
on Devices.BrandID=Brands.BrandID
inner join Warranties
on Warranties.DeviceID=Devices.DeviceID;

-- Devices whose warranty is still active
select Devices.DeviceName, Warranties.EndDate
from Devices
inner join Warranties
on Warranties.DeviceID=Devices.DeviceID
where Warranties.EndDate >= GETDATE();

-- Devices whose warranty has expired
select Devices.DeviceName, Warranties.EndDate
from Devices
inner join Warranties
on Warranties.DeviceID=Devices.DeviceID
where Warranties.EndDate < GETDATE();

-- All devices of one owner, even the ones without a warranty
select Devices.DeviceName, Warranties.EndDate
from Devices
left join Warranties
on Devices.DeviceID=Warranties.DeviceID
where Devices.OwnerAccountID = 2;

-- Authorized centers and the brand each one services
select Technicians.ServiceCenterName, Brands.BrandName
from Technicians
inner join TechnicianBrands
on TechnicianBrands.TechnicianID=Technicians.TechnicianID
inner join Brands
on TechnicianBrands.BrandID=Brands.BrandID;

-- Number of requests in each status
select Status, count(*) as TotalRequests from ServiceRequests
group by Status;

-- Technicians with average rating above 4
select TechnicianID, avg(Rating) as AverageRating, count(*) as TotalReviews from Reviews
group by TechnicianID
having avg(Rating) > 4;

-- Total repair cost of each device (repair vs replace)
select Devices.DeviceName, Devices.PurchasePrice,
sum(ServiceReports.FinalAmount) as TotalRepairCost
from Devices
inner join ServiceRequests on ServiceRequests.DeviceID=Devices.DeviceID
inner join ServiceAttempts on ServiceAttempts.RequestID=ServiceRequests.RequestID
inner join ServiceReports on ServiceReports.AttemptID=ServiceAttempts.AttemptID
group by Devices.DeviceName, Devices.PurchasePrice;

-- Devices that cost more than the average device
select * from Devices
where PurchasePrice > (select avg(PurchasePrice) from Devices);

-- Full history of one request (the same request keeps all its attempts)
select ServiceAttempts.AttemptNo, Technicians.TechnicianType, Accounts.FullName, ServiceAttempts.Status, ServiceAttempts.UnresolvedReason
from ServiceAttempts
inner join Technicians
on ServiceAttempts.TechnicianID=Technicians.TechnicianID
inner join Accounts
on Technicians.AccountID=Accounts.AccountID
where ServiceAttempts.RequestID = 204;
go

-- ---------- Views ----------

Create View vw_DeviceWarranty as
select Devices.DeviceID, Devices.OwnerAccountID, Devices.DeviceName, Brands.BrandName,
Warranties.EndDate,
case when Warranties.EndDate >= GETDATE() then 'Active' else 'Expired' end as WarrantyStatus
from Devices
inner join Brands
on Devices.BrandID=Brands.BrandID
left join Warranties
on Devices.DeviceID=Warranties.DeviceID;
go

Create View vw_RequestDetails as
select ServiceRequests.RequestID, Devices.DeviceName, Brands.BrandName, Accounts.FullName as Requester,
ServiceRequests.ServiceType, ServiceRequests.Urgency, ServiceRequests.Status
from ServiceRequests
inner join Devices
on ServiceRequests.DeviceID=Devices.DeviceID
inner join Brands
on Devices.BrandID=Brands.BrandID
inner join Accounts
on ServiceRequests.RequesterAccountID=Accounts.AccountID;
go

SELECT * FROM vw_DeviceWarranty;
SELECT * FROM vw_RequestDetails;
go

-- ---------- Procedures ----------

-- Warranty active: show ONLY the authorized centers that service the brand of this device
create Procedure sp_GetAuthorizedProviders
@DeviceID INT
as
begin
select Technicians.TechnicianID, Technicians.ServiceCenterName, Brands.BrandName, Technicians.Availability
from Devices
inner join Warranties
on Warranties.DeviceID=Devices.DeviceID
inner join TechnicianBrands
on TechnicianBrands.BrandID=Devices.BrandID
inner join Technicians
on Technicians.TechnicianID=TechnicianBrands.TechnicianID
inner join Brands
on Brands.BrandID=Devices.BrandID
where Devices.DeviceID = @DeviceID
and Technicians.TechnicianType = 'authorized'
and Warranties.EndDate >= GETDATE();
End;
go

-- Warranty expired (or the user approved the transfer): independent technicians suited to the device
create Procedure sp_GetIndependentProviders
@DeviceID INT
as
begin
select Technicians.TechnicianID, Accounts.FullName, Technicians.Availability
from Devices
inner join TechnicianCategories
on TechnicianCategories.CategoryID=Devices.CategoryID
inner join Technicians
on Technicians.TechnicianID=TechnicianCategories.TechnicianID
inner join Accounts
on Accounts.AccountID=Technicians.AccountID
inner join ProviderSubscriptions ps
on ps.TechnicianID=Technicians.TechnicianID
and ps.Status='active' and ps.EndDate >= CAST(GETDATE() AS DATE)
inner join ProviderSubscriptionPlans pp
on pp.ProviderPlanID=ps.ProviderPlanID and pp.ProviderType='independent' and pp.IsActive=1
where Devices.DeviceID = @DeviceID
and Technicians.TechnicianType = 'independent'
and Technicians.Availability = 'available'
and Technicians.IsVerified = 1
and Accounts.Status = 'active'
and not exists (select 1 from Warranties w where w.DeviceID = Devices.DeviceID and w.EndDate >= CAST(GETDATE() AS DATE));
End;
go

-- Direct assignment for an out-of-warranty request. Only subscribed, available independent technicians appear.
create or alter procedure usp_AssignIndependentProvider
@RequestID INT,
@TechnicianID INT,
@AssignedByAccountID INT
as
begin
set nocount on;
set xact_abort on;
declare @DeviceID int,@CategoryID int,@WarrantyActive bit,@RequestStatus varchar(30),
        @NewAttemptID int,@NewAttemptNo int;
select @DeviceID=rq.DeviceID,@WarrantyActive=rq.WarrantyActiveAtRequest,
       @RequestStatus=rq.Status,@CategoryID=d.CategoryID
from ServiceRequests rq inner join Devices d on d.DeviceID=rq.DeviceID
where rq.RequestID=@RequestID;
if @DeviceID is null throw 50230, 'Service request not found.', 1;
if @WarrantyActive=1 throw 50231, 'This device must be handled by its authorized service center first.', 1;
if @RequestStatus in ('completed','cancelled') throw 50232, 'This service request is closed.', 1;
if exists(select 1 from ServiceAttempts where RequestID=@RequestID and Status in ('pending','accepted','in_progress','waiting_parts'))
    throw 50233, 'This request already has an active technician.', 1;
if not exists (
    select 1 from Technicians t inner join Accounts a on a.AccountID=t.AccountID
    inner join TechnicianCategories tc on tc.TechnicianID=t.TechnicianID and tc.CategoryID=@CategoryID
    where t.TechnicianID=@TechnicianID and t.TechnicianType='independent'
      and t.Availability='available' and t.IsVerified=1 and a.Status='active'
)
    throw 50234, 'Choose an available, approved technician for this device category.', 1;
-- active subscription required (no grace period)
if not exists (
    select 1 from ProviderSubscriptions ps inner join ProviderSubscriptionPlans pp on pp.ProviderPlanID=ps.ProviderPlanID
    where ps.TechnicianID=@TechnicianID and ps.Status='active'
      and ps.EndDate>=CAST(GETDATE() AS DATE)
      and pp.ProviderType='independent' and pp.IsActive=1
)
    throw 50235, 'This technician needs an active HomeMind subscription.', 1;
set @NewAttemptID=(select isnull(max(AttemptID),0)+1 from ServiceAttempts);
set @NewAttemptNo=(select isnull(max(AttemptNo),0)+1 from ServiceAttempts where RequestID=@RequestID);
insert into ServiceAttempts (AttemptID,RequestID,AttemptNo,TechnicianID,ProviderKind,Status,AssignedByAccountID,RespondBy)
values(@NewAttemptID,@RequestID,@NewAttemptNo,@TechnicianID,'independent','pending',@AssignedByAccountID,DATEADD(minute,10,GETDATE()));
update ServiceRequests set Status='matching' where RequestID=@RequestID;
end;
go

-- The authorized center could not fix the problem: save the reason (the request is NOT moved automatically)
create Procedure sp_MarkAttemptUnresolved
@AttemptID INT,
@Reason NVARCHAR(1000)
as
begin
update ServiceAttempts
set Status='unresolved', UnresolvedReason=@Reason, FinishedAt=GETDATE()
where AttemptID = @AttemptID;

update ServiceRequests
set Status='unable_to_resolve'
where RequestID = (select RequestID from ServiceAttempts where AttemptID = @AttemptID);
End;
go

-- The user approved: start a new attempt on the SAME request with an independent technician
create Procedure sp_ContinueWithIndependent
@RequestID INT,
@TechnicianID INT
as
begin
if not exists (select 1 from ServiceRequests where RequestID = @RequestID and Status = 'unable_to_resolve')
begin
raiserror('This request is not waiting for the user decision.',16,1);
return;
end

if not exists (
    select 1 from Technicians t
    inner join Accounts a on a.AccountID=t.AccountID
    inner join ServiceRequests rq on rq.RequestID=@RequestID
    inner join Devices d on d.DeviceID=rq.DeviceID
    inner join TechnicianCategories tc on tc.TechnicianID=t.TechnicianID and tc.CategoryID=d.CategoryID
    where t.TechnicianID=@TechnicianID and t.TechnicianType='independent'
      and t.Availability='available' and t.IsVerified=1 and a.Status='active'
)
begin
raiserror('Choose an active independent technician for this device category.',16,1);
return;
end

declare @NewAttemptID int = (select isnull(max(AttemptID),0)+1 from ServiceAttempts);
declare @NewAttemptNo int = (select isnull(max(AttemptNo),0)+1 from ServiceAttempts where RequestID = @RequestID);
if not exists (
    select 1 from ProviderSubscriptions ps inner join ProviderSubscriptionPlans pp on pp.ProviderPlanID=ps.ProviderPlanID
    where ps.TechnicianID=@TechnicianID and ps.Status='active'
      and ps.EndDate>=CAST(GETDATE() AS DATE)
      and pp.ProviderType='independent' and pp.IsActive=1
)
begin
raiserror('This independent technician needs an active HomeMind subscription.',16,1);
return;
end

insert into ServiceAttempts (AttemptID, RequestID, AttemptNo, TechnicianID, ProviderKind, Status, UserApprovedTransfer, RespondBy)
values(@NewAttemptID, @RequestID, @NewAttemptNo, @TechnicianID, 'independent', 'pending', 1, DATEADD(minute,10,GETDATE()));

update ServiceRequests
set Status='matching'
where RequestID = @RequestID;
End;
go

create Procedure sp_GetDevicesByOwner
@OwnerID INT
as
begin
Select * From vw_DeviceWarranty
Where OwnerAccountID = @OwnerID;
End;
go

-- Independent technician completes the work and creates one unpaid final invoice.
-- An approved estimate is required and the invoice may be at most 10% above it.
create or alter procedure usp_CompleteIndependentService
@AttemptID INT,
@FaultFound NVARCHAR(500),
@WorkDescription NVARCHAR(2000),
@PartsReplaced NVARCHAR(500)=NULL,
@FinalAmount DECIMAL(10,2)
as
begin
set nocount on;
set xact_abort on;
declare @RequestID int,@DeviceID int,@ReportID int,@EstimateID int,@Estimated decimal(10,2);
select @RequestID=sa.RequestID,@DeviceID=rq.DeviceID
from ServiceAttempts sa
inner join ServiceRequests rq on rq.RequestID=sa.RequestID
where sa.AttemptID=@AttemptID and sa.ProviderKind='independent'
  and sa.Status in ('accepted','in_progress');
if @RequestID is null throw 50215, 'Only an active independent technician service can be completed.', 1;
if @FinalAmount is null or @FinalAmount<=0 throw 50216, 'Enter a valid final invoice amount.', 1;
select top (1) @EstimateID=EstimateID,@Estimated=EstimatedTotal
from ServiceEstimates where AttemptID=@AttemptID and Status='approved' order by EstimateID desc;
if @EstimateID is null throw 50218, 'There is no approved estimate for this job.', 1;
if @FinalAmount > @Estimated*1.10 throw 50219, 'The invoice is more than 10 percent above the approved estimate. Send a revised estimate first.', 1;
if exists(select 1 from ServiceReports where AttemptID=@AttemptID)
    throw 50217, 'A service report already exists for this attempt.', 1;
set @ReportID=(select isnull(max(ReportID),0)+1 from ServiceReports);
insert into ServiceReports (ReportID,AttemptID,EstimateID,FaultFound,WorkDescription,PartsReplaced,FinalAmount,PaymentStatus)
values(@ReportID,@AttemptID,@EstimateID,@FaultFound,@WorkDescription,@PartsReplaced,@FinalAmount,'unpaid');
update ServiceAttempts set Status='completed',FinishedAt=getdate() where AttemptID=@AttemptID;
update ServiceRequests set Status='completed',CompletedAt=getdate() where RequestID=@RequestID;
update Devices set LastServiceDate=cast(getdate() as date) where DeviceID=@DeviceID;
end;
go

-- Start one 30-day free trial after admin approval. The backend calls this once.
create or alter procedure usp_StartIndependentTechnicianTrial
@TechnicianID INT
as
begin
set nocount on;
set xact_abort on;
declare @PlanID int, @TrialDays int, @Today date=cast(getdate() as date);
if not exists(select 1 from Technicians t inner join Accounts a on a.AccountID=t.AccountID
              where t.TechnicianID=@TechnicianID and t.TechnicianType='independent'
                and t.IsVerified=1 and a.Status='active')
    throw 50200, 'Only an approved independent technician can start a trial.', 1;
if exists(select 1 from ProviderSubscriptions where TechnicianID=@TechnicianID and IsTrial=1)
    throw 50201, 'The free trial has already been used.', 1;
if exists(select 1 from ProviderSubscriptions where TechnicianID=@TechnicianID and Status='active' and EndDate>=@Today)
    throw 50202, 'An active subscription already exists.', 1;
select top (1) @PlanID=ProviderPlanID, @TrialDays=TrialDays
from ProviderSubscriptionPlans where ProviderType='independent' and IsActive=1 order by ProviderPlanID;
if @PlanID is null or isnull(@TrialDays,0)<1
    throw 50203, 'The independent technician trial is not configured.', 1;
declare @NewID int=(select isnull(max(ProviderSubscriptionID),0)+1 from ProviderSubscriptions);
insert into ProviderSubscriptions (ProviderSubscriptionID, TechnicianID, ProviderPlanID, Status, StartDate, EndDate, IsTrial)
values(@NewID,@TechnicianID,@PlanID,'active',@Today,dateadd(day,@TrialDays-1,@Today),1);
end;
go

-- Call only after the payment gateway confirms the monthly subscription payment (20 JOD technician) server-side.
create or alter procedure usp_RenewIndependentTechnicianSubscription
@ProviderSubscriptionID INT,
@VerifiedPaymentReference NVARCHAR(200)
as
begin
set nocount on;
set xact_abort on;
if nullif(ltrim(rtrim(@VerifiedPaymentReference)),N'') is null
    throw 50210, 'A verified payment reference is required.', 1;
declare @TechnicianID int, @Price decimal(10,2), @CurrentEnd date,
        @Start date, @End date, @Today date=cast(getdate() as date);
select @TechnicianID=ps.TechnicianID,@Price=pp.PriceJOD,@CurrentEnd=ps.EndDate
from ProviderSubscriptions ps
inner join ProviderSubscriptionPlans pp on pp.ProviderPlanID=ps.ProviderPlanID
inner join Technicians t on t.TechnicianID=ps.TechnicianID and t.TechnicianType='independent'
where ps.ProviderSubscriptionID=@ProviderSubscriptionID and ps.Status<>'cancelled'
  and pp.ProviderType='independent' and pp.IsActive=1;
if @TechnicianID is null throw 50211, 'Independent technician subscription not found.', 1;
if @Price is null or @Price<=0 throw 50212, 'Monthly plan price is not configured.', 1;
if exists(select 1 from ProviderSubscriptionPayments where PaymentReference=@VerifiedPaymentReference)
    throw 50213, 'Payment reference already used.', 1;
set @Start=case when @CurrentEnd>=@Today then dateadd(day,1,@CurrentEnd) else @Today end;
set @End=dateadd(day,-1,dateadd(month,1,@Start));
declare @PaymentID int=(select isnull(max(ProviderSubscriptionPaymentID),0)+1 from ProviderSubscriptionPayments);
insert into ProviderSubscriptionPayments (ProviderSubscriptionPaymentID,ProviderSubscriptionID,AmountJOD,PaymentReference,PeriodStart,PeriodEnd)
values(@PaymentID,@ProviderSubscriptionID,@Price,@VerifiedPaymentReference,@Start,@End);
update ProviderSubscriptions set Status='active',StartDate=isnull(StartDate,@Start),EndDate=@End,IsTrial=0
where ProviderSubscriptionID=@ProviderSubscriptionID;
end;
go

-- HOMEmind takes no fee from a payment and never holds the money.
-- Step 1: the customer confirmed the work and reports that they paid the technician (cash or CliQ).
create or alter procedure usp_ReportIndependentServicePayment
@ReportID INT,
@PaymentMethod VARCHAR(5)
as
begin
set nocount on;
set xact_abort on;
if @PaymentMethod not in ('cash','cliq') throw 50220, 'Payment method must be cash or cliq.', 1;
declare @Amount decimal(10,2);
select @Amount=sr.FinalAmount
from ServiceReports sr with (updlock,holdlock)
inner join ServiceAttempts sa on sa.AttemptID=sr.AttemptID
where sr.ReportID=@ReportID and sr.PaymentStatus='unpaid'
  and sa.ProviderKind='independent' and sa.Status='completed';
if @Amount is null throw 50221, 'Only an unpaid completed independent service can be reported as paid.', 1;
insert into Payments (PaymentID,ReportID,Method,Amount)
values((select isnull(max(PaymentID),0)+1 from Payments),@ReportID,@PaymentMethod,@Amount);
update ServiceReports set PaymentStatus='reported',CustomerConfirmedAt=getdate() where ReportID=@ReportID and PaymentStatus='unpaid';
if @@rowcount<>1 throw 50222, 'Invoice was already reported or changed.', 1;
update ServiceRequests set Status='payment_reported'
where RequestID=(select sa.RequestID from ServiceReports sr inner join ServiceAttempts sa on sa.AttemptID=sr.AttemptID where sr.ReportID=@ReportID);
end;
go

-- Step 2: the technician confirms that the money was received. Call it for the logged-in technician of this job only.
create or alter procedure usp_ConfirmIndependentServicePayment
@ReportID INT
as
begin
set nocount on;
set xact_abort on;
update Payments set Status='confirmed',ConfirmedAt=getdate() where ReportID=@ReportID and Status='reported';
if @@rowcount<>1 throw 50223, 'There is no reported payment to confirm.', 1;
update ServiceReports set PaymentStatus='paid' where ReportID=@ReportID;
update ServiceRequests set Status='paid'
where RequestID=(select sa.RequestID from ServiceReports sr inner join ServiceAttempts sa on sa.AttemptID=sr.AttemptID where sr.ReportID=@ReportID);
end;
go

-- Can this provider receive new requests right now?
-- in_house staff always can; independent technicians and authorized agents need a verified, active account and an
-- active subscription. When the subscription ends the provider is locked out until it is renewed.
Create View vw_ProviderCanReceiveRequests as
select t.TechnicianID, t.TechnicianType, ps.Status as SubscriptionStatus, ps.EndDate,
case
when t.TechnicianType = 'in_house' then 1
when t.IsVerified = 1 and a.Status = 'active' and ps.Status = 'active'
 and ps.EndDate >= cast(GETDATE() as date) then 1
else 0 end as CanReceiveRequests
from Technicians t
inner join Accounts a on a.AccountID = t.AccountID
left join ProviderSubscriptions ps
on ps.TechnicianID = t.TechnicianID
and ps.ProviderSubscriptionID = (select max(p2.ProviderSubscriptionID) from ProviderSubscriptions p2 where p2.TechnicianID = t.TechnicianID);
go

create Trigger trg_ServiceRequests_StatusHistory
on ServiceRequests
after update
as
begin
insert into RequestStatusHistory (HistoryID, RequestID, OldStatus, NewStatus)
select (select isnull(max(HistoryID),0) from RequestStatusHistory) + row_number() over (order by inserted.RequestID),
inserted.RequestID, deleted.Status, inserted.Status
from inserted
inner join deleted on deleted.RequestID = inserted.RequestID
where inserted.Status <> deleted.Status;
End;
go

-- The independent technician sends an estimate. A new one replaces the old one (the old one becomes 'revised').
create Procedure sp_SendEstimate
@AttemptID INT,
@Diagnosis NVARCHAR(500),
@PlannedWork NVARCHAR(1000),
@Parts DECIMAL(10,2),
@Labor DECIMAL(10,2),
@Other DECIMAL(10,2),
@PlannedDate DATE
as
begin
declare @EstimateID int = (select isnull(max(EstimateID),0)+1 from ServiceEstimates);
declare @Limit decimal(10,2) = (select Companies.ApprovalLimitJOD
 from ServiceAttempts
 inner join ServiceRequests on ServiceRequests.RequestID = ServiceAttempts.RequestID
 inner join Devices on Devices.DeviceID = ServiceRequests.DeviceID
 inner join Companies on Companies.CompanyID = Devices.CompanyID
 where ServiceAttempts.AttemptID = @AttemptID);

update ServiceEstimates set Status='revised' where AttemptID = @AttemptID and Status = 'sent';

insert into ServiceEstimates (EstimateID, AttemptID, Diagnosis, PlannedWork, PartsCost, LaborCost, OtherCost, PlannedDate, ValidUntil, NeedsManagerApproval)
values(@EstimateID, @AttemptID, @Diagnosis, @PlannedWork, @Parts, @Labor, @Other, @PlannedDate, DATEADD(hour,48,GETDATE()),
 case when @Limit is not null and (@Parts + @Labor + @Other) > @Limit then 1 else 0 end);

update ServiceRequests
set Status='estimate_sent'
where RequestID = (select RequestID from ServiceAttempts where AttemptID = @AttemptID);
End;
go

-- The customer (or the company manager) approves the estimate: the repair may start.
create Procedure sp_ApproveEstimate
@EstimateID INT,
@ByManager BIT = 0
as
begin
if exists (select 1 from ServiceEstimates where EstimateID = @EstimateID and NeedsManagerApproval = 1 and @ByManager = 0)
begin
raiserror('This estimate needs the company manager approval.',16,1);
return;
end
if exists (select 1 from ServiceEstimates where EstimateID = @EstimateID and (Status <> 'sent' or ValidUntil < GETDATE()))
begin
raiserror('This estimate is no longer open.',16,1);
return;
end

update ServiceEstimates
set Status='approved', DecidedAt=GETDATE(),
ManagerApprovedAt = case when @ByManager = 1 then GETDATE() else ManagerApprovedAt end
where EstimateID = @EstimateID;

update ServiceRequests
set Status='estimate_approved'
where RequestID = (select ServiceAttempts.RequestID from ServiceEstimates inner join ServiceAttempts on ServiceAttempts.AttemptID = ServiceEstimates.AttemptID where ServiceEstimates.EstimateID = @EstimateID);
End;
go

create Procedure sp_RejectEstimate
@EstimateID INT,
@Reason NVARCHAR(200)
as
begin
update ServiceEstimates set Status='rejected', DecidedAt=GETDATE(), RejectReason=@Reason where EstimateID = @EstimateID and Status = 'sent';

update ServiceRequests
set Status='estimate_rejected'
where RequestID = (select ServiceAttempts.RequestID from ServiceEstimates inner join ServiceAttempts on ServiceAttempts.AttemptID = ServiceEstimates.AttemptID where ServiceEstimates.EstimateID = @EstimateID);
End;
go

-- A problem after the service: only within 14 days of completion, free, and on the same request.
create Procedure sp_ReportProblem
@RequestID INT,
@AccountID INT,
@ProblemType NVARCHAR(80),
@Details NVARCHAR(1000)
as
begin
if not exists (select 1 from ServiceRequests where RequestID = @RequestID and CompletedAt is not null and DATEDIFF(day, CompletedAt, GETDATE()) <= 14)
begin
raiserror('Problems can be reported only within 14 days after the service was completed.',16,1);
return;
end

insert into ProblemReports (ProblemID, RequestID, ReportedByAccountID, ProblemType, Details)
values((select isnull(max(ProblemID),0)+1 from ProblemReports), @RequestID, @AccountID, @ProblemType, @Details);

update ServiceRequests set Status='problem_reported' where RequestID = @RequestID;
End;
go

-- Run this every minute (SQL Agent job or a background service in the API).
-- Offers nobody answered in time expire. A center that did not answer: the customer decides about an independent technician.
-- An independent request whose technician did not answer: no_provider_found (the customer chooses another technician).
create Procedure sp_ExpireOffers
as
begin
update ServiceAttempts set Status='expired' where Status = 'pending' and RespondBy < GETDATE();

update ServiceRequests
set Status = case when Status = 'center_review' then 'unable_to_resolve' else 'no_provider_found' end
where Status in ('matching','center_review')
and not exists (select 1 from ServiceAttempts where ServiceAttempts.RequestID = ServiceRequests.RequestID and ServiceAttempts.Status in ('pending','accepted','in_progress'));
End;
go

EXEC sp_GetAuthorizedProviders @DeviceID = 5;     -- LG refrigerator, warranty active -> LG centers only
EXEC sp_GetAuthorizedProviders @DeviceID = 9;     -- Samsung washing machine -> Samsung centers only
EXEC sp_GetIndependentProviders @DeviceID = 11;   -- water heater, warranty expired
EXEC sp_GetDevicesByOwner @OwnerID = 2;
EXEC sp_ContinueWithIndependent @RequestID = 204, @TechnicianID = 5;   -- after the user approves
SELECT * FROM vw_ProviderCanReceiveRequests;
-- EXEC sp_ExpireOffers;                                                  -- scheduled job
-- EXEC usp_CompleteIndependentService @AttemptID = 4, @FaultFound = 'x', @WorkDescription = 'y', @FinalAmount = 38;   -- fails above estimate + 10%

-- ==================== Authorized agent trial and renewal (30 days free, then 30 JOD / month) ====================

GO

CREATE OR ALTER PROCEDURE dbo.usp_StartAuthorizedCenterTrial
    @TechnicianID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @PlanID INT, @TrialDays INT, @Today DATE=CAST(GETDATE() AS DATE), @SubscriptionID INT;
    BEGIN TRAN;
        IF NOT EXISTS (
            SELECT 1 FROM dbo.Technicians t WITH (UPDLOCK,HOLDLOCK)
            JOIN dbo.Accounts a ON a.AccountID=t.AccountID
            WHERE t.TechnicianID=@TechnicianID AND t.TechnicianType='authorized'
              AND t.IsVerified=1 AND a.Status='active'
        ) THROW 50300, 'Only an active, verified authorized agent can start a trial.', 1;

        IF EXISTS (SELECT 1 FROM dbo.ProviderSubscriptions WITH (UPDLOCK,HOLDLOCK)
                   WHERE TechnicianID=@TechnicianID AND IsTrial=1)
            THROW 50301, 'The agent free trial has already been used.', 1;

        IF EXISTS (SELECT 1 FROM dbo.ProviderSubscriptions WITH (UPDLOCK,HOLDLOCK)
                   WHERE TechnicianID=@TechnicianID AND Status='active' AND EndDate>=@Today)
            THROW 50302, 'This agent already has an active subscription.', 1;

        SELECT TOP (1) @PlanID=ProviderPlanID,@TrialDays=TrialDays
        FROM dbo.ProviderSubscriptionPlans
        WHERE ProviderType='authorized' AND IsActive=1
        ORDER BY ProviderPlanID;
        IF @PlanID IS NULL OR ISNULL(@TrialDays,0)<1
            THROW 50303, 'The authorized agent plan is not configured.', 1;

        SET @SubscriptionID=(SELECT ISNULL(MAX(ProviderSubscriptionID),0)+1
                             FROM dbo.ProviderSubscriptions WITH (UPDLOCK,HOLDLOCK));
        INSERT dbo.ProviderSubscriptions (ProviderSubscriptionID,TechnicianID,ProviderPlanID,Status,StartDate,EndDate,IsTrial)
        VALUES (@SubscriptionID,@TechnicianID,@PlanID,'active',@Today,DATEADD(DAY,@TrialDays-1,@Today),1);
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RenewAuthorizedCenterSubscription
    @ProviderSubscriptionID INT,
    @VerifiedPaymentReference NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NULLIF(LTRIM(RTRIM(@VerifiedPaymentReference)),N'') IS NULL
        THROW 50310, 'A verified subscription payment reference is required.', 1;

    DECLARE @TechnicianID INT,@PlanID INT,@Price DECIMAL(10,2),@CurrentEnd DATE,
            @PeriodStart DATE,@PeriodEnd DATE,@Today DATE=CAST(GETDATE() AS DATE),@PaymentID INT;
    BEGIN TRAN;
        SELECT @TechnicianID=ps.TechnicianID,@PlanID=ps.ProviderPlanID,
               @CurrentEnd=ps.EndDate,@Price=pp.PriceJOD
        FROM dbo.ProviderSubscriptions ps WITH (UPDLOCK,HOLDLOCK)
        JOIN dbo.ProviderSubscriptionPlans pp ON pp.ProviderPlanID=ps.ProviderPlanID
        JOIN dbo.Technicians t ON t.TechnicianID=ps.TechnicianID AND t.TechnicianType='authorized'
        WHERE ps.ProviderSubscriptionID=@ProviderSubscriptionID
          AND ps.Status<>'cancelled' AND pp.ProviderType='authorized' AND pp.IsActive=1;
        IF @TechnicianID IS NULL THROW 50311, 'Authorized agent subscription not found.', 1;
        IF @Price IS NULL OR @Price<=0 THROW 50312, 'The authorized agent monthly price is invalid.', 1;
        IF EXISTS (SELECT 1 FROM dbo.ProviderSubscriptionPayments WHERE PaymentReference=@VerifiedPaymentReference)
            THROW 50313, 'This payment reference has already been used.', 1;

        SET @PeriodStart=CASE WHEN @CurrentEnd>=@Today THEN DATEADD(DAY,1,@CurrentEnd) ELSE @Today END;
        SET @PeriodEnd=DATEADD(DAY,-1,DATEADD(MONTH,1,@PeriodStart));
        SET @PaymentID=(SELECT ISNULL(MAX(ProviderSubscriptionPaymentID),0)+1
                        FROM dbo.ProviderSubscriptionPayments WITH (UPDLOCK,HOLDLOCK));
        INSERT dbo.ProviderSubscriptionPayments (ProviderSubscriptionPaymentID,ProviderSubscriptionID,AmountJOD,PaymentReference,PeriodStart,PeriodEnd)
        VALUES (@PaymentID,@ProviderSubscriptionID,@Price,@VerifiedPaymentReference,@PeriodStart,@PeriodEnd);
        UPDATE dbo.ProviderSubscriptions
        SET Status='active',StartDate=COALESCE(StartDate,@PeriodStart),EndDate=@PeriodEnd,IsTrial=0
        WHERE ProviderSubscriptionID=@ProviderSubscriptionID;
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetProviderAccessStatus
    @AccountID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.AccountID,a.AccountType,t.TechnicianType,
           CASE WHEN EXISTS (
               SELECT 1 FROM dbo.ProviderSubscriptions ps
               JOIN dbo.ProviderSubscriptionPlans pp ON pp.ProviderPlanID=ps.ProviderPlanID
               WHERE ps.TechnicianID=t.TechnicianID AND ps.Status='active'
                 AND ps.EndDate>=CAST(GETDATE() AS DATE) AND pp.IsActive=1
                 AND pp.ProviderType=CASE WHEN t.TechnicianType='independent' THEN 'independent' WHEN t.TechnicianType='authorized' THEN 'authorized' END
           ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS HasActiveSubscription,
           (SELECT TOP (1) ps.EndDate FROM dbo.ProviderSubscriptions ps
             JOIN dbo.ProviderSubscriptionPlans pp ON pp.ProviderPlanID=ps.ProviderPlanID
             WHERE ps.TechnicianID=t.TechnicianID AND ps.Status='active' AND pp.IsActive=1
             ORDER BY ps.EndDate DESC) AS SubscriptionEndDate
    FROM dbo.Accounts a
    LEFT JOIN dbo.Technicians t ON t.AccountID=a.AccountID
    WHERE a.AccountID=@AccountID AND t.TechnicianType IN ('independent','authorized');
END;
GO

-- Only active, verified and subscribed centers are available for warranty requests.
CREATE OR ALTER PROCEDURE dbo.sp_GetAuthorizedProviders
    @DeviceID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.TechnicianID,t.ServiceCenterName,b.BrandName,t.Availability
    FROM dbo.Devices d
    JOIN dbo.Warranties w ON w.DeviceID=d.DeviceID AND w.EndDate>=GETDATE()
    JOIN dbo.TechnicianBrands tb ON tb.BrandID=d.BrandID
    JOIN dbo.Technicians t ON t.TechnicianID=tb.TechnicianID AND t.TechnicianType='authorized'
    JOIN dbo.Brands b ON b.BrandID=d.BrandID
    JOIN dbo.Accounts a ON a.AccountID=t.AccountID AND a.Status='active'
    JOIN dbo.ProviderSubscriptions ps ON ps.TechnicianID=t.TechnicianID AND ps.Status='active' AND ps.EndDate>=CAST(GETDATE() AS DATE)
    JOIN dbo.ProviderSubscriptionPlans pp ON pp.ProviderPlanID=ps.ProviderPlanID AND pp.ProviderType='authorized' AND pp.IsActive=1
    WHERE d.DeviceID=@DeviceID AND t.IsVerified=1 AND t.Availability='available';
END;
GO
