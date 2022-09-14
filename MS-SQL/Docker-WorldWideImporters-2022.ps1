##############################################################################################################################
#
# PowerShell script to create image of SQL in docker
#
# Links :
#      https://docs.microsoft.com/en-us/sql/linux/tutorial-restore-backup-in-sql-server-container?view=sql-server-ver15
#      https://blog.sqlauthority.com/2019/03/06/sql-server-how-to-get-started-with-docker-containers-with-latest-sql-server/
#
##############################################################################################################################
#
$ServerName   = "sql22-local"          # SQL instance name
$password     = "Pass@Word1"           # SQL SA password
$sharedFolder = "C:\Projects\Docker"   # Shared folder between you machine and docker
#
#
# Clear the host output window
    clear

# Get latest SQL image
docker pull mcr.microsoft.com/mssql/server:2022-latest

# Create SQL container

docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=${password}" `
-p 11143:1433 --name $ServerName `
-v ${sharedFolder}:/sql `
-d mcr.microsoft.com/mssql/server:2022-latest

# start container
docker start $ServerName

# show status of all containers 	
docker container ls -a

# Create backup folder in the container
docker exec -it $ServerName mkdir /var/opt/mssql/backup

# Download backup file
curl -OutFile "wwi22.bak" "https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak"

# Use docker cp to copy the backup file into the container in the /var/opt/mssql/backup directory.
docker cp wwi22.bak ${ServerName}:/var/opt/mssql/backup

# Restore database
docker exec -it $ServerName /opt/mssql-tools/bin/sqlcmd -S localhost `
   -U SA -P "${password}" `
   -Q "RESTORE FILELISTONLY FROM DISK = '/var/opt/mssql/backup/wwi22.bak'"
#
docker exec -it $ServerName /opt/mssql-tools/bin/sqlcmd `
   -S localhost -U SA -P "${password}" `
   -Q "RESTORE DATABASE WideWorldImporters22 FROM DISK = '/var/opt/mssql/backup/wwi22.bak' WITH MOVE 'WWI_Primary' TO '/var/opt/mssql/data/WideWorldImporters22.mdf', MOVE 'WWI_UserData' TO '/var/opt/mssql/data/WideWorldImporters22_userdata.ndf', MOVE 'WWI_Log' TO '/var/opt/mssql/data/WideWorldImporters22.ldf', MOVE 'WWI_InMemory_Data_1' TO '/var/opt/mssql/data/WideWorldImporters22_InMemory_Data_1'"
#
# Verify restore
docker exec -it $ServerName /opt/mssql-tools/bin/sqlcmd `
   -S localhost -U SA -P "${password}" `
   -Q "SELECT Name FROM sys.Databases"

#
############################################
#
#  SSMS
#
#  1. Open SSMS
#  2. ServerName : localhost,11143
#  3. Login      : sa
#  4. password   : Pass@Word1
#
############################################
#
# Manual download sample backup file from
#  https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0