# Repository Mirroring Tool
[![Build Status](https://travis-ci.org/SUSE/rmt.svg?branch=master)](https://travis-ci.org/SUSE/rmt)
[![Code Climate](https://codeclimate.com/github/SUSE/rmt.png)](https://codeclimate.com/github/SUSE/rmt)
[![Coverage Status](https://coveralls.io/repos/SUSE/rmt/badge.svg?branch=master&service=github)](https://coveralls.io/github/SUSE/rmt?branch=master)

This tool allows you to mirror RPM repositories in your own private network.
Organization (mirroring) credentials are required to mirror SUSE repositories.

Basic usage instructions for the version packaged and shipped in SUSE and openSUSE distributions can be found in the [manual of rmt-cli](MANUAL.md).

## Installation on SLE15

1. Activate your instance of SLE15 via `SUSEConnect -r <regcode>`
2. Activate Server Applications module `SUSEConnect -p sle-module-server-applications/15/x86_64`
3. Install RMT with YaST installation wizard `zypper in rmt-server yast2-rmt`
4. Run installation wizard for RMT `yast2 rmt` and configure your instance

## Installation on OpenSUSE Leap 15

1. Install RMT with YaST installation wizard `zypper in rmt-server yast2-rmt`
2. Run installation wizard for RMT `yast2 rmt` and configure your instance

## Manual installation and configuration

RMT currently gets built for these distributions: `SLE_15`, `SLE_12_SP2`, `SLE_12_SP3`, `openSUSE_Leap_42.2`, `openSUSE_Leap_42.3`, `openSUSE_Tumbleweed`.
To add the repository, call: (replace `<dist>` with your distribution)

`zypper ar -f https://download.opensuse.org/repositories/systemsmanagement:/SCC:/RMT/<dist>/systemsmanagement:SCC:RMT.repo`

To install RMT, run: `zypper in rmt-server`

After installation configure your RMT instance:

* Prepare the database:
    * Start MySQL/MariaDB by running `systemctl start mysql`
    * Set database `root` user password by running `mysqladmin -u root password`
    * Make sure you can access to the database console as `root` user by running `mysql -u root -p`
    * Create a MySQL/MariaDB user with the following command:
    ```
    mysql -u root -p <<EOFF
    GRANT ALL PRIVILEGES ON \`rmt\`.* TO rmt@localhost IDENTIFIED BY 'rmt';
    FLUSH PRIVILEGES;
    EOFF
    ```
* See the "Configuration" section for how to configure the options in `/etc/rmt.conf`.
* Start RMT by running `systemctl start rmt-server`. This will start the RMT server at http://localhost:4224.
* By default, mirrored repositories are saved under `/usr/share/rmt/public`, which is a symlink that points to
`/var/lib/rmt/public`. In order to change destination directory, recreate `/usr/share/rmt/public` symlink to point to the
desired location.

## Dependencies

Supported Ruby versions are 2.5.0 and newer.

## Development setup

* Install the dependencies:
  * `sudo zypper in libxml2-devel libxslt-devel`
  * `bundle install`
* Copy the file `config/rmt.yml` to `config/rmt.local.yml` to override the default settings:
    * Add your organization credentials to `scc` section
    * Add your MySQL credentials

* Setup MySQL/MariaDB:

* Grant the just configured database user access to your database. The following command will grant access to the default user `rmt` with password `rmt` (run it as root):

```
mysql -u root <<EOFF
GRANT ALL PRIVILEGES ON \`rmt%\`.* TO rmt@localhost IDENTIFIED BY 'rmt';
FLUSH PRIVILEGES;
EOFF
```
* Create databases by running `rails db:create db:migrate`
* Run `rails server` to run the web-server

### Packaging

**Notes:**

* The package is built in OBS at: https://build.opensuse.org/package/show/systemsmanagement:SCC:RMT/rmt-server
* To update the version of RMT, you will have to change the following files:
  * `Makefile`
  * `lib/rmt.rb`
  * `package/rmt-server.spec`

1. Checkout/update OBS working copy:
      * If the OBS project is not checked out, check out working copy of OBS project into a separate directory, e.g.:
          ```
          mkdir ~/obs
          cd ~/obs
          osc co systemsmanagement:SCC:RMT rmt-server
          ```
      * Alternatively, if OBS working copy is already checked out, update the working copy by running `osc up`
2. Run `make dist` in your RMT working directory to build a tarball.
3. Copy the files from the `package` directory to the OBS working directory.
4. Build the package with osc:

    `osc build <repository> <arch> --no-verify`

    The list of all build targets and architectures that configured for the project can be obtained by running `osc repos`.

5. Examine the changes by running `osc status` and `osc diff`.
6. Stage the changes by running `osc addremove`.
7. Commit the changes into OBS by running `osc ci`.

### Running with docker-compose

In order to run the application locally using docker-compose:

1. Copy `.env.example` file to `.env`;
2. Add your organization credentials to `.env` file. Mirroring credentials can be obtained from the [SUSE Customer Center](https://scc.suse.com/organization);
3. Start the containers by running `docker-compose up`. Running `docker-compose up -d` will start the containers in the background;
4. Execute commands in the container, e.g.:
    ```bash
    docker-compose exec rmt rmt-cli repos --help
    ```
    Alternatively, running `docker-compose exec rmt bash` will start the shell inside the container.
5. The web server will be accessible at [http://localhost:8080/](http://localhost:8080/), this URL can be used for registering clients.

## Is it any good?

[Yes.](https://news.ycombinator.com/item?id=3067434)

## RMT and SMT

RMT is replacing some functionality of [SMT](https://github.com/SUSE/smt). Following table outlines differences and similarities between the two tools. Last SLE version where SMT is available is 12. From version 15 onward only RMT is offered.

| Feature/Tech      | SMT           | RMT           |
|-------------------|---------------|---------------|
|Available on SLES11|:white_check_mark:|:x:|
|Available on SLES12|:white_check_mark:|:x:|
|Available on SLES15|:x:|:white_check_mark:|
|Sync products data from SCC|:white_check_mark:|:white_check_mark:|
|Mirror RPMs from repositories|:white_check_mark:|:white_check_mark:|
|Selective mirroring(which products to mirror)|:white_check_mark:|:white_check_mark:|
|Serve RPMs via http|:white_check_mark:|:white_check_mark:|
|Registration of SLE 15 systems|:white_check_mark:|:white_check_mark:|
|Registration of SLE 12 systems|:white_check_mark:|:white_check_mark:|
|Registration of SLE 11 systems|:white_check_mark:|:x:|
|Migration support SLE 12 > 15|:white_check_mark:|:white_check_mark:|
|Staging repositories|:white_check_mark:|:x:<sup>[1](#staging)</sup>|
|Air gap sync/mirroring for secure environments|:white_check_mark:|:white_check_mark:|
|NTLM Proxy support|:white_check_mark:|:white_check_mark:|
|Custom repositories|:white_check_mark:|:white_check_mark:|
|YaST installation wizard|:white_check_mark:|:white_check_mark:|
|YaST management wizard|:white_check_mark:|:x:|
|Client management|:white_check_mark:|:x:|
|RedHat support (Extended Support)|:white_check_mark:|:x:<sup>[2](#res)</sup>|
|Files deduplication|:white_check_mark:|:white_check_mark:|
|Data transfer from SMT to RMT|-|:white_check_mark:|
|Transfer registration data to SCC|:white_check_mark:|:x:|
|Reporting|:white_check_mark:|:x:|
|Custom TLS certificates for web-server|:white_check_mark:|:white_check_mark:|
|Webserver|Apache2|Nginx|
|Database|mariadb|mariadb|
|Platform|Perl|Ruby|

<a name="staging">1</a>: Functionality is offered by [SUSE Manager](https://www.suse.com/documentation/suse-best-practices/susemanager/data/susemanager.html)  
<a name="res">2</a>: RES support is planned for SLES15 SP1

## Feedback

Do you have suggestions for improvement? Let us know!

Go to [Issues](https://github.com/SUSE/rmt/issues/new), create a new issue and describe what you think could be improved.

Feedback is always welcome!
