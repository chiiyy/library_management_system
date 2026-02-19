# Library Management System MySQL Database Design

## Project Summary
This project is a **MySQL based Library Management System database** built to support core library operations. It covers:
- Catalog and resource records (physical and digital)
- User profiles for Students and Lecturers
- Librarian management
- Borrow, return, and view activity tracking
- Fine and payment handling
- Overdue related notifications

---

## Project Goals
- Build a relational database for a university style library environment.
- Automate borrowing rules, due dates, and penalty handling using SQL logic.
- Apply database fundamentals such as relationships, constraints, and triggers.

---

## Key Functionalities

### 1. Catalog and Resource Records
- Maintains both physical items and digital resources.
- Organises resources by title, subject area, author, publisher, and rack location.
- Allows digital items to be available without quantity limits.

### 2. User Accounts and Access Rules
- Supports two user roles: Student and Lecturer.
- Stores details including gender, date of birth, department, and major.
- Includes a restriction or ban mechanism for users with overdue items or unpaid fines.

### 3. Borrowing and Returning Flow
- Tracks actions such as Borrow, Return, and View.
- Automatically assigns due dates during borrowing.
- Records late returns and damage or lost conditions when applicable.

### 4. Fines, Payments, and Invoices
- Computes fines automatically based on overdue duration.
- Stores payment details for both purchases and fine settlements.
- Generates invoices as part of the payment workflow.

### 5. Notifications
- Tracks overdue days for active borrowings.
- Sends fine related notifications to users when returns trigger penalties.

---

## Database Design

### Core Tables
- `Rack`
- `Author`
- `Publisher`
- `KnowledgeResource`
- `User`
- `Librarian`
- `Transaction`
- `Payment`
- `Notification`

---

## SQL Triggers Included
- **CombinedTransactionTrigger**
  - Prevents restricted users from borrowing.
  - Assigns due dates automatically.
  - Updates overdue status and fine related values.

- **CopyBookPriceToPurchasePrice**
  - Transfers the resource price into the purchase payment field.

- **AutoGeneratePaymentAndNotificationAfterReturn**
  - Creates payment records and notifications automatically after a return event.

---

## Tools and Concepts
- MySQL
- SQL trigger automation
- Relational database modelling
- ERD and EERD design

---

## Setup Instructions
1. Launch **MySQL Workbench** or **phpMyAdmin**
2. Import `library_management_system.sql`
3. Run the script to create the database and tables

---

## Included Sample Records
The script comes with pre loaded data such as:
- 15 users
- 5 librarians
- 38 resources
- Example racks, authors, publishers, and transactions

---

## Skills Practised
- ER modelling and schema planning
- Table creation and relationship constraints
- Foreign keys and validation rules
- Trigger based automation
- Managing transaction workflows

## ERD
![ERD](Screenshots/ERD.png)

