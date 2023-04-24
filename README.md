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

**NOTE:**

- The backups will be copied by default to `<BACKUP_DIRECTORY>/<DB_HOST>/` (e.g.: `$HOME/postgres/localhost/`). Where `BACKUP_DIRECTORY` is the value of `--backup-directory` script argument (by default `$HOME/postgres`) and `DB_HOST` is the value of the `--host` script argument.
- By default is exported the databases ownership, to skip this set the `--no-owner` script argument.
- Executes the script without arguments or by passing `-h | --help` to see all available options.

## License

MIT

## Author Information

By: [Carlos M Bustillo Rdguez](https://linkedin.com/in/carlosbustillordguez/)
