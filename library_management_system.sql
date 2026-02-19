CREATE DATABASE IF NOT EXISTS library19_4;
USE library19_4;

CREATE TABLE Rack
(
    RackID VARCHAR(10) NOT NULL,
    Floor VARCHAR(10) NOT NULL,
    ShelfNumber INT NOT NULL, 
    PRIMARY KEY (RackID)
);

CREATE TABLE Author
(
    AuthorID VARCHAR(10) NOT NULL,
    AuthorName VARCHAR(20) NOT NULL,
    AuthorGender VARCHAR(10) NOT NULL,
    AuthorNationality VARCHAR(10) NOT NULL,
    PRIMARY KEY (AuthorID)
);

CREATE TABLE Publisher
(
    PublisherID VARCHAR(10) NOT NULL,
    PublisherName VARCHAR(20) NOT NULL,
    PRIMARY KEY (PublisherID)
);

CREATE TABLE KnowledgeResource
(
    ResourceID VARCHAR(10) NOT NULL,
    Title VARCHAR(20) NOT NULL,
    Type VARCHAR(20) NOT NULL CHECK (Type IN ('PhysicalContent', 'DigitalContent')), 
    Subject VARCHAR(20) NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity >= 0),  
    BookPrice decimal(10,2) NULL,
    RackID VARCHAR(10) NULL,
    PublisherID VARCHAR(10) NOT NULL,
    AuthorID VARCHAR(10) NOT NULL,
    FOREIGN KEY (RackID) REFERENCES Rack(RackID),
    FOREIGN KEY (PublisherID) REFERENCES Publisher(PublisherID),
    FOREIGN KEY (AuthorID) REFERENCES Author(AuthorID),
    PRIMARY KEY (ResourceID),
    Language VARCHAR(255),
    Pages INT CHECK (Pages > 0), 
    Format VARCHAR(255),
    FileSize DOUBLE CHECK (FileSize > 0), 
    PlatformCompatibility VARCHAR(255)
);

CREATE TABLE User
(
    UserID VARCHAR(10) NOT NULL,
    UserName VARCHAR(20) NOT NULL,
    UserPassword VARCHAR(20) NOT NULL,
    UserMobileNo VARCHAR(15) NOT NULL,
    UserGender VARCHAR(10) NOT NULL,
    UserDOB DATE NOT NULL,
    Restricted BOOL NOT NULL DEFAULT false,  
    Role VARCHAR(10) NOT NULL CHECK (Role IN ('Student', 'Lecturer')), 
    Major VARCHAR(255),
    EnrollmentYear YEAR,
    Department VARCHAR(255),
    Title VARCHAR(255),
    ResearchField VARCHAR(255),
    PRIMARY KEY (UserID)
);

CREATE TABLE Librarian
(
    LibID VARCHAR(10) NOT NULL,
    LibName VARCHAR(20) NOT NULL,
    LibPassword VARCHAR(20) NOT NULL,
    LibMobileNo VARCHAR(15) NOT NULL,
    LibGender VARCHAR(10) NOT NULL,
    LibDOB DATE NOT NULL,
    EmploymentDate DATE NOT NULL DEFAULT (CURRENT_DATE),  
    PRIMARY KEY (LibID)
);

CREATE TABLE Transaction
(
    TransactionID VARCHAR(10) NOT NULL,
    TransactionType VARCHAR(10) NOT NULL CHECK (TransactionType IN ('Return', 'Borrow', 'View')),
    Status VARCHAR(20) NOT NULL CHECK (Status IN ('Active', 'Damage/Lost', 'Damage/Lost + Late', 'Late', 'Complete', 'Viewed')),  
    TransactionDate DATE NOT NULL DEFAULT (CURRENT_DATE), 
    TransactionTime TIME NOT NULL DEFAULT (CURRENT_TIME),
    DueDate DATE NULL DEFAULT (CURRENT_DATE),
    DueTime TIME NULL DEFAULT (CURRENT_TIME),
    OverduePrice decimal(10,2),
    UserID VARCHAR(10) NOT NULL,
    ResourceID VARCHAR(10),
    LibrarianID VARCHAR(10), -- Added column for LibrarianID
    FOREIGN KEY (UserID) REFERENCES User(UserID),
    FOREIGN KEY (ResourceID) REFERENCES KnowledgeResource(ResourceID),
    FOREIGN KEY (LibrarianID) REFERENCES Librarian(LibID), -- Added foreign key constraint
    PRIMARY KEY (TransactionID)
);

CREATE TABLE Payment
(
    InvoiceNo VARCHAR(20) NOT NULL,
    TotalAmount DOUBLE NULL CHECK (TotalAmount > 0),  
    PaymentDate DATE NOT NULL DEFAULT (CURRENT_DATE),  
    PaymentMethod VARCHAR(30) NOT NULL CHECK (PaymentMethod IN ('Purchase', 'FinePayment', 'FinePayment + Purchase')),  
    FineAmount DOUBLE NULL CHECK (FineAmount >= 0), 
    PurchasePrice DOUBLE,
    ResourceID VARCHAR(10) NOT NULL,
    UserID VARCHAR(10) NOT NULL,
	TransactionID VARCHAR(10),
    FOREIGN KEY (ResourceID) REFERENCES KnowledgeResource(ResourceID),
    FOREIGN KEY (UserID) REFERENCES User(UserID),
	FOREIGN KEY (TransactionID) REFERENCES Transaction(TransactionID),
    PRIMARY KEY (InvoiceNo)
);

CREATE TABLE Notification
(
    NotificationID VARCHAR(10) NOT NULL, 
    NumberOfOverdueDays INT CHECK (NumberOfOverdueDays >= 0), 
    FineAmount DOUBLE NOT NULL CHECK (FineAmount >= 0), 
    UserID VARCHAR(10) NOT NULL,
    TransactionID VARCHAR(10),
    FOREIGN KEY (UserID) REFERENCES User(UserID),
    FOREIGN KEY (TransactionID) REFERENCES Transaction(TransactionID),
    PRIMARY KEY (NotificationID)
);

DELIMITER //
CREATE TRIGGER CombinedTransactionTrigger
BEFORE INSERT ON Transaction
FOR EACH ROW
BEGIN
    DECLARE borrowCount INT;
    DECLARE isRestricted BOOL;
    DECLARE borrowDateTime DATETIME;
    DECLARE returnDateTime DATETIME;
    DECLARE gracePeriod INT DEFAULT 14;
    DECLARE overdueDays INT;
    DECLARE borrowTransactionID VARCHAR(10);

    -- Check if the user is restricted
    SELECT Restricted INTO isRestricted FROM User WHERE UserID = NEW.UserID;

    -- Allow viewing even for restricted users
    IF isRestricted AND NOT (NEW.TransactionType = 'View' AND NEW.Status = 'Viewed') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Restricted user cannot borrow books.';
    END IF;

    -- Count the number of books already borrowed by the user on the same day
    SELECT COUNT(*) INTO borrowCount 
    FROM Transaction 
    WHERE UserID = NEW.UserID 
    AND TransactionDate = NEW.TransactionDate 
    AND TransactionType = 'Borrow';

    IF NEW.TransactionType = 'Borrow' AND borrowCount >= 15 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot borrow more than 15 books on the same day.';
    END IF;

    IF NEW.TransactionType = 'Borrow' THEN
        -- Set due date and time for 'Borrow' transactions
        SET NEW.DueDate = DATE_ADD(NEW.TransactionDate, INTERVAL 14 DAY);
        SET NEW.DueTime = NEW.TransactionTime;

    ELSEIF NEW.TransactionType = 'Return' THEN
        -- Find the 'Borrow' transaction ID
        SELECT TransactionID INTO borrowTransactionID
        FROM Transaction
        WHERE UserID = NEW.UserID 
          AND ResourceID = NEW.ResourceID 
          AND TransactionType = 'Borrow'
        ORDER BY TransactionDate DESC, TransactionTime DESC
        LIMIT 1;

        -- Get the date and time of the 'Borrow' transaction
        SELECT CONCAT(TransactionDate, ' ', TransactionTime) INTO borrowDateTime
        FROM Transaction
        WHERE TransactionID = borrowTransactionID;

        -- Set the return date and time
        SET returnDateTime = CONCAT(NEW.TransactionDate, ' ', NEW.TransactionTime);

        -- Calculate the number of overdue days
        SET overdueDays = TIMESTAMPDIFF(DAY, borrowDateTime, returnDateTime) - gracePeriod;

        -- Determine if the book is late
        IF overdueDays > 0 THEN
            -- Book is late
            SET NEW.OverduePrice = overdueDays * 0.20;
            
            -- Check if the book is also marked as 'Damage/Lost'
            IF NEW.Status = 'Damage/Lost' THEN
                SET NEW.Status = 'Damage/Lost + Late';
            ELSE
                SET NEW.Status = 'Late';
            END IF;
        ELSE
            -- Book is not late
            SET NEW.OverduePrice = 0;
            
            -- If the book is marked as 'Damage/Lost', keep the status
            IF NEW.Status = 'Damage/Lost' THEN
                SET NEW.Status = 'Damage/Lost';
            ELSE
                SET NEW.Status = 'Complete';
            END IF;
        END IF;
    END IF;
END;
//
DELIMITER ;

DELIMITER //
CREATE TRIGGER CopyBookPriceToPurchasePrice
BEFORE INSERT ON Payment
FOR EACH ROW
BEGIN
    IF NEW.PaymentMethod = 'Purchase' THEN
        -- Temporary variable for storing the book price
        SET @bookPrice := (SELECT BookPrice FROM KnowledgeResource WHERE ResourceID = NEW.ResourceID);

        -- Set the PurchasePrice in Payment table to the retrieved BookPrice
        SET NEW.PurchasePrice = @bookPrice;
    END IF;
END;
//
DELIMITER ;

DELIMITER //
CREATE TRIGGER AutoGeneratePaymentAndNotificationAfterReturn
AFTER INSERT ON Transaction
FOR EACH ROW
BEGIN
    DECLARE dueDateTime DATETIME;
    DECLARE returnDateTime DATETIME;
    DECLARE overdueDays INT;
    DECLARE fineAmount DOUBLE;

DELIMITER //
CREATE TRIGGER AutoGeneratePaymentAndNotificationAfterReturn
AFTER INSERT ON Transaction
FOR EACH ROW
BEGIN
    DECLARE dueDateTime DATETIME;
    DECLARE returnDateTime DATETIME;
    DECLARE overdueDays INT;
    DECLARE fineAmount DOUBLE DEFAULT 0;  -- Default value set to 0

    IF NEW.TransactionType = 'Return' THEN
        -- Retrieve the maximum invoice number, remove the leading character, increment by 1
        SET @maxInvoiceNo := (SELECT MAX(CAST(SUBSTRING(InvoiceNo, 2) AS UNSIGNED)) FROM Payment);
        SET @nextInvoiceNo := IFNULL(@maxInvoiceNo, 0) + 1;

        -- Format the next invoice number as 'I' followed by the number, padded with zeros
        SET @invoiceNo := CONCAT('I', LPAD(@nextInvoiceNo, 3, '0'));

        -- Get the due date and time from the corresponding 'Borrow' transaction
        SELECT CONCAT(DueDate, ' ', DueTime) INTO dueDateTime
        FROM Transaction
        WHERE UserID = NEW.UserID 
          AND ResourceID = NEW.ResourceID 
          AND TransactionType = 'Borrow'
        ORDER BY TransactionDate DESC, TransactionTime DESC
        LIMIT 1;

        -- Set the return date and time
        SET returnDateTime = CONCAT(NEW.TransactionDate, ' ', NEW.TransactionTime);

        -- Calculate the number of overdue days
        SET overdueDays = GREATEST(TIMESTAMPDIFF(DAY, dueDateTime, returnDateTime), 0);

        -- Determine payment method based on transaction status and type
        SET @paymentMethod := CASE
                                WHEN NEW.Status = 'Damage/Lost + Late' THEN 'FinePayment + Purchase'
                                WHEN NEW.Status = 'Late' THEN 'FinePayment'
                                WHEN NEW.Status = 'Complete' AND NEW.TransactionType = 'Return' AND overdueDays <= 0 THEN 'FinePayment'
                                ELSE 'Purchase'
                              END;

        -- Determine fine amount and book price
        SET @fineAmount := IF(NEW.OverduePrice IS NOT NULL AND NEW.OverduePrice > 0, NEW.OverduePrice, 0);
        SET @bookPrice := (SELECT BookPrice FROM KnowledgeResource WHERE ResourceID = NEW.ResourceID);

        -- Set PurchasePrice based on payment method
        SET @purchasePrice := CASE
                                WHEN @paymentMethod = 'Purchase' OR @paymentMethod = 'FinePayment + Purchase' THEN @bookPrice
                                ELSE NULL
                              END;

        -- Calculate total amount
        SET @totalAmount := CASE
                             WHEN @paymentMethod = 'FinePayment + Purchase' THEN @fineAmount + @purchasePrice
                             WHEN @paymentMethod = 'FinePayment' THEN @fineAmount
                             WHEN @paymentMethod = 'Purchase' THEN @purchasePrice
                             ELSE 0
                            END;

        -- Ensure fine amount and total amount are not negative
        SET @fineAmount := GREATEST(@fineAmount, 0);
        SET @totalAmount := GREATEST(@totalAmount, 0);

        -- Insert into Payment table only if total amount is greater than zero
        IF @totalAmount > 0 THEN
            INSERT INTO Payment (InvoiceNo, TotalAmount, PaymentMethod, FineAmount, PurchasePrice, ResourceID, UserID, TransactionID)
            VALUES (@invoiceNo, @totalAmount, @paymentMethod, @fineAmount, @purchasePrice, NEW.ResourceID, NEW.UserID, NEW.TransactionID);
        END IF;

        -- Retrieve the maximum notification number, remove the leading character, increment by 1
        SET @maxNotificationNo := (SELECT MAX(CAST(SUBSTRING(NotificationID, 2) AS UNSIGNED)) FROM Notification);
        SET @nextNotificationNo := IFNULL(@maxNotificationNo, 0) + 1;

        -- Format the next notification number as 'N' followed by the number, padded with zeros
        SET @notificationID := CONCAT('N', LPAD(@nextNotificationNo, 3, '0'));

        -- Get the fine amount from the newly created payment record
        SELECT TotalAmount INTO fineAmount
        FROM Payment
        WHERE InvoiceNo = @invoiceNo;

        -- Insert into Notification table
        INSERT INTO Notification (NotificationID, NumberOfOverdueDays, FineAmount, UserID, TransactionID)
        VALUES (@notificationID, overdueDays, fineAmount, NEW.UserID, NEW.TransactionID);
    END IF;
END;
//
DELIMITER ;

INSERT INTO User (UserID, UserName, UserPassword, UserMobileNo, UserGender, UserDOB, Restricted, Role, Major, EnrollmentYear, Department, Title, ResearchField) VALUES
('U001', 'John', 'password123', '1234567890', 'Male', '2000-06-23', TRUE, 'Student', 'Computer Science', '2020', NULL, NULL, NULL),
('U002', 'Joshua', 'password321', '0987654321', 'Male', '1989-02-02', FALSE, 'Lecturer', NULL, NULL, 'Computer Science', 'Professor', 'Artificial Intelligence'),
('U003', 'Chiiyen', 'yenn3845', '0123456789', 'Female', '1988-05-05', FALSE, 'Lecturer', NULL, NULL, 'Mathematics', 'Associate Professor', 'Algebra'),
('U004', 'Emily', 'emily1234', '2345678901', 'Female', '2005-03-15', FALSE, 'Student', 'Marine Biotechnology', '2023', NULL, NULL, NULL),
('U005', 'Sophia', 'sophia5678', '3456789012', 'Female', '1979-07-21', FALSE, 'Lecturer', NULL, NULL, 'Literature', 'Senior Lecturer', '19th Century Novels'),
('U006', 'Ethan', 'ethan91011', '4567890123', 'Male', '1984-11-30', FALSE, 'Lecturer', NULL, NULL, 'Physics', 'Lecturer', 'Quantum Mechanics'),
('U007', 'Isabella', 'bella12345', '5678901234', 'Female', '2001-01-08', FALSE, 'Student', 'Advertising', '2021', NULL, NULL, NULL),
('U008', 'Mason', 'mason7890', '6789012345', 'Male', '1974-04-17', FALSE, 'Lecturer', NULL, NULL, 'Engineering', 'Professor', 'Structural Engineering'),
('U009', 'Olivia', 'olivia5432', '7890123456', 'Female', '2004-09-26', TRUE, 'Student', 'Finance', '2023', NULL, NULL, NULL),
('U010', 'Liam', 'liam13579', '8901234567', 'Male', '2002-12-12', FALSE, 'Student', 'English Language and Literature', '2020', NULL, NULL, NULL),
('U011', 'Keisha', 'KEi34u32', '3568083995', 'Female', '2003-12-22', FALSE, 'Student', 'Data Science', '2021', NULL, NULL, NULL),
('U012', 'Carina', 'carrii3472', '9864696257', 'Female', '2002-03-19', FALSE, 'Student', 'International Business', '2022', NULL, NULL, NULL),
('U013', 'Winnie', 'winnieee3493', '6878525868', 'Female', '2002-08-31', FALSE, 'Student', 'Cyber Security', '2021', NULL, NULL, NULL),
('U014', 'Soe', 'soe273639', '2366273994', 'Male', '2002-04-03', FALSE, 'Student', 'Economics', '2020', NULL, NULL, NULL),
('U015', 'Jacky', 'Alphatonn', '563829385', 'Male', '2000-05-03', FALSE, 'Student', 'Electrical Engineering', '2021', NULL, NULL, NULL);

INSERT INTO Librarian (LibID, LibName, LibPassword, LibMobileNo, LibGender, LibDOB, EmploymentDate)
VALUES
    ('L001', 'Sally', 'Cupcake11', '1234567890', 'Male', '1980-01-15', '2022-01-15'),
    ('L002', 'Susanne', '123456', '2345678901', 'Female', '1985-03-25', '2022-02-01'),
    ('L003', 'Fawzia', 'Fawzia1@', '3456789012', 'Male', '1990-06-10', '2022-03-10'),
    ('L004', 'Abdul', 'Abdullll', '4567890123', 'Female', '1995-08-20', '2022-04-05'),
    ('L005', 'Fajar', 'FajarWajar', '5678901234', 'Male', '2000-10-05', '2022-05-15');

INSERT INTO Rack (RackID, Floor, ShelfNumber) VALUES 
('R001', '1st', 5),
('R002', '1st', 4),
('R003', '1st', 6),
('R004', '2nd', 6),
('R005', '2nd', 5),
('R006', '2nd', 4),
('R007', '3rd', 6),
('R008', '3rd', 3),
('R009', '3rd', 5),
('R010', '3rd', 4);

INSERT INTO Author (AuthorID, AuthorName, AuthorGender, AuthorNationality) 
VALUES 
('A001', 'James Patterson', 'Male', 'American'),
('A002', 'Fyodor Dostoevsky', 'Male', 'Russian'),
('A003', 'Oscar Wilde', 'Male', 'Irish'),
('A004', 'James Joyce', 'Male', 'Irish'),
('A005', 'J K Rowling', 'Female', 'British'),
('A006', 'William Shakespeare', 'Male', 'British'),
('A007', 'Hajime Isayama', 'Male', 'Japanese'),
('A008', 'Sun Tzu', 'Male', 'Chinese'),
('A009', 'Yan Lianke', 'Male', 'Chinese'),
('A010', 'Dame Agatha Christie', 'Female', 'British'),	
('A011', 'Laura Smith', 'Female', 'Canadian'),
('A012', 'Robert Brown', 'Male', 'American'),
('A013', 'Alice Johnson', 'Female', 'Australian'),
('A014', 'Michael Davis', 'Male', 'British'),
('A015', 'Sarah Wilson', 'Female', 'Irish');

INSERT INTO Publisher (PublisherID, PublisherName) 
VALUES 
('P001', 'Bloomsbury'),                 
('P002', 'Methuen & Co'),              
('P003', 'Military Text'),             
('P004', "Stationers' Hall"),           
('P005', 'Russian Messenger'),      
('P006', 'Kodansha'),                 
('P007', 'B. W. Huebsch'),             
('P008', 'Chatto & Windus'),    
('P009', 'Brown & Company'),
('P010', 'Collins Crime Club'),  
('P011', 'Academic Press'),
('P012', 'Global Maps'),
('P013', 'Science House'),
('P014', 'Historic Publishers'),
('P015', 'Digital Media Co.');

INSERT INTO KnowledgeResource 
(ResourceID, Title, Type, Subject, Quantity, BookPrice, RackID, PublisherID, AuthorID, Language, Pages, Format, FileSize, PlatformCompatibility) 
VALUES 
('KR001', 'Crooked house', 'PhysicalContent', 'Mystery', 3, '63.49', 'R001', 'P010', 'A010', 'English', 300, NULL, NULL, NULL),
('KR002', 'Art of War', 'PhysicalContent', 'History', 2, '129.32', 'R006', 'P003', 'A008', 'Chinese', 400, NULL, NULL, NULL),
('KR003', 'Digital Fortress', 'DigitalContent', 'Thriller', 999999, NULL, NULL, 'P009', 'A001', 'English', 429, 'E-book', 2.0, 'All Platforms'),
('KR004', 'Irish Tales', 'PhysicalContent', 'Fiction', 5, '146.21', 'R004', 'P002', 'A003', 'English', 200, NULL, NULL, NULL),
('KR005', 'Romeo and Juliet', 'DigitalContent', 'Drama', 999999, NULL, NULL, 'P004', 'A006', 'English', NULL, 'Audio', 1.5, 'iOS/Android'),
('KR006', 'Russian Classics', 'PhysicalContent', 'Literature', 4, '165.24', 'R003', 'P005', 'A002', 'Russian', 500, NULL, NULL, NULL),
('KR007', 'Wizards and Witches', 'DigitalContent', 'Fantasy', 999999, NULL, NULL, 'P001', 'A005', 'English', 360, 'E-book', 3.0, 'Windows/Mac'),
('KR008', 'Attack On Titan', 'PhysicalContent', 'Manga', 6, '99.99', 'R005', 'P006', 'A007', 'Japanese', 190, NULL, NULL, NULL),
('KR009', 'Modern China', 'PhysicalContent', 'Sociology', 3, '299.99', 'R002', 'P008', 'A009', 'Chinese', 250, NULL, NULL, NULL),
('KR010', 'Joycean Stream', 'DigitalContent', 'Literature', 999999, NULL, NULL, 'P007', 'A004', 'English', 325, 'E-book', 2.5, 'All Platforms'),
('KR011', 'The Lost Symbol', 'PhysicalContent', 'Mystery', 4, '183.43', 'R001', 'P010', 'A010', 'English', 350, NULL, NULL, NULL),
('KR012', 'The Labyrinth', 'PhysicalContent', 'Adventure', 2, '283.56', 'R002', 'P010', 'A010', 'English', 280, NULL, NULL, NULL),
('KR013', 'The Secret Chamber', 'PhysicalContent', 'Mystery', 5, '123.23', 'R001', 'P010', 'A010', 'English', 320, NULL, NULL, NULL),
('KR014', 'Macbeth', 'DigitalContent', 'Drama', 999999, NULL, NULL, 'P004', 'A006', 'English', NULL, 'Audio', 1.6, 'iOS/Android'),
('KR015', 'The Chase', 'PhysicalContent', 'Thriller', 3, '137.43', 'R006', 'P009', 'A001', 'English', 310, NULL, NULL, NULL),
('KR016', 'The Warning', 'PhysicalContent', 'Thriller', 4, '58.93', 'R006', 'P009', 'A001', 'English', 290, NULL, NULL, NULL),
('KR017', 'White Nights', 'PhysicalContent', 'Literature', 3, '59.99', 'R003', 'P005', 'A002', 'Russian', 240, NULL, NULL, NULL),
('KR018', 'The Adolescent', 'PhysicalContent', 'Literature', 2, '97.82', 'R003', 'P005', 'A002', 'Russian', 410, NULL, NULL, NULL),
('KR019', 'Crime and Punishment', 'DigitalContent', 'Literature', 999999, NULL, NULL, 'P005', 'A002', 'Russian', 430, 'E-book', 2.8, 'All Platforms'),
('KR020', 'War Principles', 'PhysicalContent', 'Philosophy', 4, '79.93', 'R002', 'P003', 'A008', 'Chinese', 180, NULL, NULL, NULL),
('KR021', 'Battlefield Tactics', 'PhysicalContent', 'History', 5, '69.74', 'R006', 'P003', 'A008', 'Chinese', 190, NULL, NULL, NULL),
('KR022', 'Strategic Warfare', 'PhysicalContent', 'History', 3, '174.42', 'R006', 'P003', 'A008', 'Chinese', 210, NULL, NULL, NULL),
('KR023', 'The Cursed Child', 'PhysicalContent', 'Fantasy', 6, '162.68', 'R001', 'P001', 'A005', 'English', 330, NULL, NULL, NULL),
('KR024', 'Data Science', 'DigitalContent', 'Science', 999999, NULL, NULL, 'P011', 'A011', 'English', 300, 'E-book', 2.1, 'All Platforms'),
('KR025', 'Calculus', 'PhysicalContent', 'Math', 10, '184.38', 'R008', 'P012', 'A012', 'English', 350, NULL, NULL, NULL),
('KR026', 'Physics IA', 'DigitalContent', 'Physics', 999999, NULL, NULL, 'P013', 'A013', 'English', 434, 'E-book', 2.32, 'All Platforms'),
('KR027', 'Java Program', 'DigitalContent', 'Computing', 999999, NULL, NULL, 'P011', 'A014', 'English', 485, 'E-book', 2.6, 'All Platforms'),
('KR028', 'Germany', 'DigitalContent', 'History', 999999, NULL, NULL, 'P012', 'A015', 'English', 320, 'Map', 1.32, 'Windows/Mac'),
('KR029', 'Biology', 'DigitalContent', 'Biology', 999999, NULL, NULL, 'P013', 'A011', 'English', 353, 'E-book', 1.8, 'All Platforms'),
('KR030', 'Chemistry', 'PhysicalContent', 'Chemistry', 8, '172.22', 'R007', 'P011', 'A012', 'English', 123, NULL, NULL, NULL),
('KR031', 'Astrophysics', 'PhysicalContent', 'Physics', 2, '137.29', 'R007', 'P012', 'A013', 'English', 234, NULL, NULL, NULL),
('KR032', 'Harry Potter', 'PhysicalContent', 'Mystery', 9, '127.24', 'R001', 'P013', 'A005', 'English', 275, NULL, NULL, NULL),
('KR033', 'Literature', 'DigitalContent', 'Arts', 999999, NULL, NULL, 'P011', 'A014', 'English', 234, 'E-book', 1.9, 'All Platforms'),
('KR034', 'Geography', 'PhysicalContent', 'Geography', 7, '185.38', 'R009', 'P012', 'A015', 'English', 264, NULL, NULL, NULL),
('KR035', 'Philosophy', 'PhysicalContent', 'Philosophy', 6, '210.48', 'R009', 'P013', 'A011', 'English', 296, NULL, NULL, NULL),
('KR036', 'Art History', 'PhysicalContent', 'History', 4, '247.38', 'R006', 'P011', 'A012', 'English', 256, NULL, NULL, NULL),
('KR037', 'Music is Fun', 'PhysicalContent', 'Music', 5, '253.22', 'R010', 'P012', 'A013', 'English', 261, NULL, NULL, NULL),
('KR038', 'Python for newbie', 'DigitalContent', 'Computing', 999999, NULL, NULL, 'P013', 'A014', 'English', 453, 'E-book', 2.5, 'All Platforms');

INSERT INTO Transaction (TransactionID, TransactionType, Status, TransactionDate, TransactionTime, UserID, ResourceID, LibrarianID) VALUES 
('T001', 'Borrow', 'Active', '2023-01-01', '15:06:50', 'U005', 'KR023', 'L001'),
('T002', 'Return', 'Damage/Lost', '2023-01-10', '05:06:00', 'U005', 'KR023', 'L001'),
('T003', 'Borrow', 'Active', '2023-03-01', '18:57:03', 'U011', 'KR011', 'L004'),
('T004', 'Borrow', 'Active', '2023-03-10', '20:08:35', 'U002', 'KR001', 'L004'),
('T005', 'Return', 'Complete', '2023-03-10', '20:12:00', 'U011', 'KR011', 'L004'),
('T006', 'View', 'Viewed', '2023-03-24', '10:34:55', 'U009', 'KR010', NULL),
('T007', 'Return', 'Complete', '2023-04-08', '22:08:00', 'U002', 'KR001', 'L005'),
('T008', 'Borrow', 'Active', '2023-04-10', '11:57:00', 'U002', 'KR002', 'L005'),
('T009', 'View', 'Viewed', '2023-04-11', '17:29:56', 'U015', 'KR014', NULL),
('T010', 'Borrow', 'Active', '2023-05-08', '21:47:05', 'U007', 'KR016', 'L002'),
('T011', 'Return', 'Complete', '2023-05-10', '00:57:14', 'U002', 'KR002', 'L002'),
('T012', 'Borrow', 'Active', '2023-06-01', '19:34:03', 'U008', 'KR008', 'L002'),
('T013', 'Return', 'Complete', '2023-06-13', '12:06:00', 'U008', 'KR008', 'L002'),
('T014', 'Borrow', 'Active', '2023-06-28', '15:34:26', 'U010', 'KR016', 'L003'),
('T015', 'Borrow', 'Active', '2023-07-03', '10:32:40', 'U010', 'KR023', 'L003'),
('T016', 'View', 'Viewed', '2023-07-10', '08:52:21', 'U003', 'KR003', NULL),
('T017', 'Return', 'Damage/Lost', '2023-07-12', '15:34:00', 'U010', 'KR016', 'L003'),
('T018', 'Return', 'Complete', '2023-07-25', '17:26:00', 'U010', 'KR023', 'L001'),
('T019', 'View', 'Viewed', '2023-07-25', '02:28:37', 'U012', 'KR029', NULL),
('T020', 'Borrow', 'Active', '2023-08-06', '01:04:20', 'U004', 'KR004', 'L001'),
('T021', 'Borrow', 'Active', '2023-08-25', '13:29:00', 'U015', 'KR015', 'L001'),
('T022', 'View', 'Viewed', '2023-09-29', '11:40:22', 'U006', 'KR038', NULL),
('T023', 'Borrow', 'Active', '2023-11-11', '18:54:00', 'U004', 'KR017', 'L005'),
('T024', 'Borrow', 'Active', '2023-11-25', '19:26:10', 'U014', 'KR030', 'L005'),
('T025', 'Return', 'Complete', '2023-12-02', '09:48:00', 'U014', 'KR030', 'L005'),
('T026', 'Return', 'Damage/Lost', '2023-12-12', '14:12:00', 'U004', 'KR017', 'L002'),
('T027', 'Borrow', 'Active', '2024-01-01', '08:55:13', 'U013', 'KR013', 'L002');