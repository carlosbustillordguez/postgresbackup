# PostgreSQL Backups

Dumps all PostgreSQL databases from a given server and optionally, backup the roles and permissions.

## Requirements

- The following tools must be installed:
  - `postgresql-client`
  - `gzip`
  - `gunzip`

## How to use the script

1- Clone this repository.

2- Add the execution permissions to the script:

```bash
chmod +x postgresbackup.sh
```

3- To backup all databases (incuding ownership) and the roles from a Postgres instances running at `localhost:5432`:

```bash
./postgresbackup.sh --host localhost -u postgres -p mysecretpassword --backup-roles
```

**NOTES:**

- The backups will be copied by default to `<BACKUP_DIRECTORY>/<DB_HOST>/` (e.g.: `$HOME/postgres/localhost/`). Where `BACKUP_DIRECTORY` is the value of `--backup-directory` script argument (by default `$HOME/postgres`) and `DB_HOST` is the value of the `--host` script argument.
- By default when `--backup-roles` is set, the passwords for roles are included in the dump. But in Azure Database for PostgreSQL Flexible Server users are not allowed to access `pg_authid` table which contains information about database authorization identifiers together with user's passwords. Therefore retrieving passwords for users (even the `postgres` admin user) is not possible; to avoid errors set `--backup-roles --no-role-passwords` to dump all the roles names without passwords.
- By default is exported the databases ownership, to skip this set the `--no-owner` script argument.
- By default is excluded the `postgres` database from the databases dump. To exclude more databases, set for example `--exclude-dbs 'postgres|azure_maintenance|azure_sys'`
- Executes the script without arguments or by passing `-h | --help` to see all available options.

## License

MIT

## Author Information

By: [Carlos M Bustillo Rdguez](https://linkedin.com/in/carlosbustillordguez/)
