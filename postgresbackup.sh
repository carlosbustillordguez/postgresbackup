#!/bin/bash
set -eo pipefail
#
# Dumps all PostgreSQL databases from a given server and optionally, backup the roles and permissions.
#
# Usage:
#   ./postgresbackup.sh --host DB_HOST -u DB_USER -p DB_PASSWORD
#
# Example:
#   ./postgresbackup.sh --host localhost -u postgres -p DB_PASSWORD
#
# By Carlos Bustillo <https://linkedin.com/in/carlosbustillordguez/>
#

### Functions ###

#######################################################################
# Print the script usage.
# Globals:
#   None.
# Arguments:
#   None.
# Outputs:
#   the script usage.
#######################################################################
print_usage() {
  echo "
Dumps all PostgreSQL databases from a given server and optionally, backup the roles and permissions.

USAGE: $(basename "$0") --host DB_HOST -u DB_USER -p DB_PASSWORD [optional arguments]

Required arguments:

  --host DB_HOST                        A PostgreSQL database host.
  -u|--user DB_USER                     The database user name.
  -p|--password DB_PASSWORD             The database user password.

Optional arguments:

  -h|--help                             Print this help and exit.
  -p|--port DB_PORT                     The database port number. Default value '5432'.
  --backup-directory BACKUP_DIRECTORY   Base backup directory. Default value '$HOME/postgres'.
  --backup-roles                        Whether to backup or not the roles and permissions. Default value 'false'.
  --remove-backups-from DAYS            Remove old backups from (-mtime compatible format for the find command). Default value '+5'.
  --exclude-dbs EXCLUDE_DBS             Regex with the databases to exclude in the dump. Default value 'postgres'.
  --no-owner                            Skip restoration of the database ownership. By default is exported the database ownership.
  --ssl                                 Whether or with what priority a secure SSL TCP/IP connection will be negotiated with the
                                        server. When is set, the 'PGSSLMODE=\"require\"' environment variable is defined.
                                        By default the variable is not defined.
    "
} # => print_usage()

#######################################################################
# Configure the environment.
# Globals:
#   None.
# Arguments:
#   None.
# Outputs:
#   NEXCHAIN_PLATFORM_HOME - the absolute script working directory
#######################################################################
configure_environment() {
  # Script directory
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  export SCRIPT_DIR

  # Source the getopt bash implementation (cross-platform version)
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}"/getopt.bash
} # => configure_environment()

#######################################################################
# Parse script options.
# Globals:
# DB_HOST                 - the PostgreSQL server hostname (value of --host)
# DB_USER                 - the user name to perform the operations (value of -u | --user)
# DB_PASSWORD             - the user name password to perform the operations (value of -p | --password)
# DB_PORT                 - the Postgres server port (value of --port)
#                           Default value '5432'
# BACKUP_DIRECTORY        - base backup directory (value of --backup-directory)
#                           Default value '$HOME/postgres'
# REMOVE_OLD_BACKUP_FROM  - remove old backups from (-mtime compatible format for the find command)
#                           Default value '+5'
# EXCLUDE_DBS             - regex with the databases to exclude in the dump (value of --exclude-dbs)
#                           Default value 'postgres'
# BACKUP_ROLES            - whether or not to backup roles (argument --backup-roles). Default value 'false'
# NO_OWNER                - skip restoration of the database ownership. By default is exported the database ownership
# PGSSLMODE              -  whether or with what priority a secure SSL TCP/IP connection will be negotiated with the server.
#                           When is set, the the 'PGSSLMODE="require"' environment variable is defined.
#                           By default the variable is not defined
# Arguments:
#   $@ (array)            - the script's arguments
#######################################################################
parse_cmdline() {
  # Global variables
  export DB_HOST DB_USER DB_PASSWORD
  export DB_PORT="5432"
  export BACKUP_DIRECTORY="$HOME/postgres"
  export REMOVE_OLD_BACKUP_FROM="+5"
  export EXCLUDE_DBS="postgres"
  export BACKUP_ROLES="false"
  export NO_OWNER=""

  # Parse arguments
  declare argv
  argv=$(getopt -o u:,p:,h --long host:,user:,password:,port:,backup-directory:,remove-backups-from:,exclude-dbs:,backup-roles,no-owner,ssl,help -- "$@") || return
  # string-split and glob-expand the contents of $argv, putting the first in $1, the second in $2, etc.
  eval "set -- $argv"

  while true; do
    case $1 in
      -h | --help)
        print_usage
        exit 0
        ;;
      --host)
        shift
        DB_HOST=$1
        shift
        ;;
      -u | --user)
        shift
        DB_USER=$1
        shift
        ;;
      -p | --password)
        shift
        DB_PASSWORD=$1
        shift
        ;;
      --port)
        shift
        DB_PORT=$1
        shift
        ;;
      --backup-directory)
        shift
        BACKUP_DIRECTORY=$1
        shift
        ;;
      --remove-backups-from)
        shift
        REMOVE_OLD_BACKUP_FROM=$1
        shift
        ;;
      --exclude-dbs)
        shift
        EXCLUDE_DBS=$1
        shift
        ;;
      --backup-roles)
        BACKUP_ROLES="true"
        shift
        ;;
      --no-owner)
        NO_OWNER="--no-owner"
        shift
        ;;
      --ssl)
        export PGSSLMODE="require"
        shift
        ;;
      --)
        break
        ;;
    esac
  done
} # => parse_cmdline()

#######################################################################
# Check script arguments.
# Globals:
#   None
# Arguments:
#   resource_group_name - a valid Azure Resource Group name
#   node_name           - the name of the Nexchain Node to deploy to
#######################################################################
check_arguments() {
  local db_host="$1"
  local db_user="$2"
  local db_password="$3"

  if [ -z "$db_host" ] || [ -z "$db_user" ] || [ -z "$db_password" ]; then
    echo "$(basename "$0"): Required arguments not passed."
    print_usage
    exit 1
  fi
} # => check_arguments()

#######################################################################
# Check the script requirements.
# Globals:
#   BACKUP_ROLES_DIRECTORY - the base backup role directory
# Arguments:
#   None.
#######################################################################
check_requirements() {
  # Base backup directory
  if [ ! -d "$BACKUP_DIRECTORY" ]; then
    mkdir -p "$BACKUP_DIRECTORY"
    echo -e "\n==> Created base backup directory: '$BACKUP_DIRECTORY'..."
  fi

  # Check for required tools
  if [ -z "$(command -v pg_dump)" ]; then
    echo "The 'postgresql-client' package is not installed in the system!!"
    echo "Please install it: apt install postgresql-client"
    exit 1
  fi

  if [ -z "$(command -v gzip)" ]; then
    echo "The 'gzip' package is not installed in the system!!"
    echo "Please install it: apt install gzip"
    exit 1
  fi

  if [ -z "$(command -v gunzip)" ]; then
    echo "The 'gunzip' package is not installed in the system!!"
    echo "Please install it: apt install gunzip"
    exit 1
  fi
} # => check_requirements()

#######################################################################
# Create a pgpass file at '/tmp/pgpass.$$'.
# Globals:
#   PGPASSFILE - the pgpass file to use
# Arguments:
#   db_host     - the Postgres server hostname
#   db_port     - the Postgres server port
#   db_user     - a valid user to perform the operations
#   db_password - the valid password for the user
#######################################################################
create_pgpass() {
  local db_host="$1"
  local db_port="$2"
  local db_user="$3"
  local db_password="$4"

  export PGPASSFILE="/tmp/pgpass.$$"
  echo "$db_host:$db_port:*:$db_user:$db_password" > $PGPASSFILE
  chmod 600 $PGPASSFILE
} # => create_pgpass()

#######################################################################
# Print formatted message error.
# Globals:
#   None.
# Arguments:
#   message     - the message to print
#######################################################################
print_error() {
  local message=$1
  echo "$message"
} # => print_error()

#######################################################################
# Backup only the roles.
# Globals:
#   None.
# Arguments:
#   db_host     - the Postgres server hostname
#   db_port     - the Postgres server port
#   db_user     - a valid user to perform the operations
#######################################################################
backup_users_roles() {
  local db_host="$1"
  local db_port="$2"
  local db_user="$3"

  echo -e "\n==> Started roles backup..."

  # Final backup directory
  if [ ! -d "$BACKUP_DIRECTORY/$db_host/" ]; then
    mkdir -p "$BACKUP_DIRECTORY/$db_host/"
  fi

  local roles_backup_file
  roles_backup_file="$BACKUP_DIRECTORY/$db_host/roles-$db_host-$(date +%Y%m%d).sql"

  if pg_dumpall -h "$db_host" -p "$db_port" -U "$db_user" --roles-only --file "$roles_backup_file"; then
    echo "Saved roles at '$roles_backup_file'."
  else
    print_error "The roles backup has been failed"
  fi
} # => backup_users_roles()

#######################################################################
# Backup the databases.
# Globals:
#   None.
# Arguments:
#   db_host     - the Postgres server hostname
#   db_port     - the Postgres server port
#   db_user     - a valid user to perform the operations
#######################################################################
# shellcheck disable=2120 # ignore function arguments
backup_postgres_dbs() {
  local db_host="$1"
  local db_port="$2"
  local db_user="$3"

  echo -e "\n==> Started databases backup..."

  set +e
  # Get all databases name
  local databases
  databases=$(
    psql -h "$db_host" -p "$db_port" -U "$db_user" -d postgres \
      -c "SELECT datname FROM pg_database WHERE datistemplate = false;" \
      | grep -Ev "datname|^---|^\(.* row.*\)" \
      | awk '{print $1}' \
      | sed '/^$/d' \
      | grep -Ev "$EXCLUDE_DBS"
  )

  if [ -n "$databases" ]; then
    for database in $databases; do
      echo "Database: $database"

      # Final backup directory
      if [ ! -d "$BACKUP_DIRECTORY/$db_host/" ]; then
        mkdir -p "$BACKUP_DIRECTORY/$db_host/"
      fi

      local database_backup_file
      database_backup_file="$BACKUP_DIRECTORY/$db_host/db-$database-$(date +%Y%m%d).sql.gz"

      # Dump the given database
      if pg_dump -h "$db_host" -p "$db_port" -U "$db_user" --dbname "$database" \
        --create --clean $NO_OWNER | gzip > "$database_backup_file"; then
        echo -e "Saved '$database' database backup at '$database_backup_file'.\n"
      else
        print_error "The dump for $database database has been failed"
        continue
      fi
    done
  fi
} # => backup_postgres_dbs()

main() {
  # Configure environment
  configure_environment

  # Parse and check arguments
  parse_cmdline "$@"
  check_arguments "$DB_HOST" "$DB_USER" "$DB_PASSWORD"

  # Check the script requirements
  check_requirements

  # Create a temporary pgpass to authenticate
  create_pgpass "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASSWORD"

  # Backup all users and their grants in a .sql file
  if [ "$BACKUP_ROLES" == "true" ]; then
    backup_users_roles "$DB_HOST" "$DB_PORT" "$DB_USER"
  fi

  # Backup PostgreSQL databases
  backup_postgres_dbs "$DB_HOST" "$DB_PORT" "$DB_USER"

  # TODO: improve
  # Remove old backup files
  find "$BACKUP_DIRECTORY" -type f -mtime "$REMOVE_OLD_BACKUP_FROM" -print0 | xargs -r0 rm -f

  # Remove the temporary pgpass
  rm -f "$PGPASSFILE"
}

## Main
[ "${BASH_SOURCE[0]}" != "$0" ] || main "$@"
