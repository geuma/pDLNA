package PDLNA::Database;

=head1 NAME

package PDLNA::Database - to mange connection and dmlto database.

=head1 DESCRIPTION

This package manages the interaction with the database such as initialising it,
executing ddl to create tables, dml to select, insert, update and delete data and
log the execution and results of queries.  Generally the query text is formed in
the other modules

=cut


use strict;
use warnings;

=head1 LIBRARY FUNCTIONS

=over 12

=item internal libraries

=begin html

</p>
<a href="./Config.html">PDLNA::Config</a>,
<a href="./Log.html">PDLNA::Log</a>.
</p>

=end html

=item external libraries

L<DBI>.

=back

=cut

use DBI;

use PDLNA::Config;
use PDLNA::Log;

=head1 METHODS

=over

=item connect() - manage connection to database.


=cut

sub connect
{
	my $dbh = undef;
	if ($CONFIG{'DB_TYPE'} eq 'SQLITE3')
	{
		$dbh = DBI->connect('dbi:SQLite:dbname='.$CONFIG{'DB_NAME'},'','', {
			PrintError => 0,
			RaiseError => 0,
		},) || PDLNA::Log::fatal('Cannot connect to database: '.$DBI::errstr);
	}
	return $dbh;
}

=item disconnect() - manage disconnection from database.


=cut

sub disconnect
{
	my $dbh = shift;
	$dbh->disconnect() || PDLNA::Log::log('ERROR: Unable to disconnect from database: '.$DBI::errstr, 0, 'database');
}

=item initialize_db() - initialise the database with fresh tables and seed data.


=cut

sub initialize_db
{
	my $dbh = PDLNA::Database::connect();

	my @tables = select_db_tables($dbh);
	if (grep(/^METADATA$/, @tables))
	{
		my @results = ();
		select_db(
			$dbh,
			{
				'query' => 'SELECT VALUE FROM METADATA WHERE KEY = ?',
				'parameters' => [ 'DBVERSION', ],
			},
			\@results,
		);

		# check if DB was build with a different database version of pDLNA
		if (!defined($results[0]->{VALUE}) || $results[0]->{VALUE} ne $CONFIG{'PROGRAM_DBVERSION'})
		{
			$dbh->do('DELETE FROM METADATA;');

			insert_db(
				$dbh,
				{
					'query' => 'INSERT INTO METADATA (KEY, VALUE) VALUES (?,?)',
					'parameters' => [ 'DBVERSION', $CONFIG{'PROGRAM_DBVERSION'}, ],
				},
			);
			insert_db(
				$dbh,
				{
					'query' => 'INSERT INTO METADATA (KEY, VALUE) VALUES (?,?)',
					'parameters' => [ 'VERSION', PDLNA::Config::print_version(), ],
				},
			);
			insert_db(
				$dbh,
				{
					'query' => 'INSERT INTO METADATA (KEY, VALUE) VALUES (?,?)',
					'parameters' => [ 'TIMESTAMP', time(), ],
				},
			);

			$dbh->do('DROP TABLE FILES;') if grep(/^FILES$/, @tables);
			$dbh->do('DROP TABLE FILEINFO;') if grep(/^FILEINFO$/, @tables);
			$dbh->do('DROP TABLE DIRECTORIES;') if grep(/^DIRECTORIES$/, @tables);
			$dbh->do('DROP TABLE SUBTITLES;') if grep(/^SUBTITLES$/, @tables);
			$dbh->do('DROP TABLE DEVICE_IP;') if grep(/^DEVICE_IP$/, @tables);
			$dbh->do('DROP TABLE DEVICE_BM;') if grep(/^DEVICE_BM$/, @tables);
			$dbh->do('DROP TABLE DEVICE_UDN;') if grep(/^DEVICE_UDN$/, @tables);
			$dbh->do('DROP TABLE DEVICE_NTS;') if grep(/^DEVICE_NTS$/, @tables);
			$dbh->do('DROP TABLE DEVICE_SERVICE;') if grep(/^DEVICE_SERVICE$/, @tables);
			$dbh->do('DROP TABLE STAT_MEM;') if grep(/^STAT_MEM$/, @tables);
			$dbh->do('DROP TABLE STAT_ITEMS;') if grep(/^STAT_ITEMS$/, @tables);
			@tables = ();
		}
	}
	else
	{
		$dbh->do('CREATE TABLE METADATA (
				KEY					VARCHAR(128) PRIMARY KEY,
				VALUE				VARCHAR(128)
			);'
		);

		insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO METADATA (KEY, VALUE) VALUES (?,?)',
				'parameters' => [ 'DBVERSION', $CONFIG{'PROGRAM_DBVERSION'}, ],
			},
		);
		insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO METADATA (KEY, VALUE) VALUES (?,?)',
				'parameters' => [ 'VERSION', PDLNA::Config::print_version(), ],
			},
		);
		insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO METADATA (KEY, VALUE) VALUES (?,?)',
				'parameters' => [ 'TIMESTAMP', time(), ],
			},
		);
	}

	unless (grep(/^FILES$/, @tables))
	{
		$dbh->do("CREATE TABLE FILES (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,

				NAME				VARCHAR(2048),
				PATH				VARCHAR(2048),
				FULLNAME			VARCHAR(2048),
				FILE_EXTENSION		VARCHAR(4),

				DATE				BIGINT,
				SIZE				BIGINT,

				MIME_TYPE			VARCHAR(128),
				TYPE				VARCHAR(12),
				EXTERNAL			BOOLEAN,

				ROOT				BOOLEAN,
				SEQUENCE			BIGINT
			);"
		);
	}

	unless (grep(/^FILEINFO$/, @tables))
	{
		$dbh->do("CREATE TABLE FILEINFO (
				FILEID_REF			INTEGER PRIMARY KEY,
				VALID				BOOLEAN,

				WIDTH				INTEGER,
				HEIGHT				INTEGER,

				DURATION			INTEGER,
				BITRATE				INTEGER,
				VBR					BOOLEAN,

				CONTAINER			VARCHAR(128),
				AUDIO_CODEC			VARCHAR(128),
				VIDEO_CODEC			VARCHAR(128),

				ARTIST				VARCHAR(128),
				ALBUM				VARCHAR(128),
				TITLE				VARCHAR(128),
				GENRE				VARCHAR(128),
				YEAR				VARCHAR(4),
				TRACKNUM			INTEGER
			);"
		);
	}

	#
	# TABLE DESCRIPTION
	#
	# TYPE
	# 	0		directory
	# 	1		playlist
	unless (grep(/^DIRECTORIES$/, @tables))
	{
		$dbh->do("CREATE TABLE DIRECTORIES (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,

				NAME				VARCHAR(2048),
				PATH				VARCHAR(2048),
				DIRNAME				VARCHAR(2048),

				ROOT				BOOLEAN,
				TYPE				INTEGER
			);"
		);
	}

	unless (grep(/^SUBTITLES$/, @tables))
	{
		$dbh->do("CREATE TABLE SUBTITLES (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,
				FILEID_REF			INTEGER,

				TYPE				VARCHAR(2048),
				MIME_TYPE			VARCHAR(128),
				NAME				VARCHAR(2048),
				FULLNAME			VARCHAR(2048),

				DATE				BIGINT,
				SIZE				BIGINT
			);"
		);
	}

	unless (grep(/^DEVICE_IP$/, @tables))
	{
		$dbh->do("CREATE TABLE DEVICE_IP (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,

				IP					VARCHAR(15),
				USER_AGENT			VARCHAR(128),
				LAST_SEEN			BIGINT
			);"
		);
	}

	unless (grep(/^DEVICE_BM$/, @tables))
	{
		$dbh->do("CREATE TABLE DEVICE_BM (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,
				DEVICE_IP_REF		INTEGER,

				FILE_ID_REF			INTEGER,
				POS_SECONDS			INTEGER
			);"
		);
	}

	unless (grep(/^DEVICE_UDN$/, @tables))
	{
		$dbh->do("CREATE TABLE DEVICE_UDN (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,
				DEVICE_IP_REF		INTEGER,

				UDN					VARCHAR(64),
				SSDP_BANNER			VARCHAR(256),
				DESC_URL			VARCHAR(512),
				RELA_URL			VARCHAR(512),
				BASE_URL			VARCHAR(512),

				TYPE				VARCHAR(256),
				MODEL_NAME			VARCHAR(256),
				FRIENDLY_NAME		VARCHAR(256)
			);"
		);
	}

	unless (grep(/^DEVICE_NTS$/, @tables))
	{
		$dbh->do("CREATE TABLE DEVICE_NTS (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,
				DEVICE_UDN_REF		INTEGER,

				TYPE				VARCHAR(128),
				EXPIRE				BIGINT
			);"
		);
	}

	unless (grep(/^DEVICE_SERVICE$/, @tables))
	{
		$dbh->do("CREATE TABLE DEVICE_SERVICE (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,
				DEVICE_UDN_REF		INTEGER,

				SERVICE_ID			VARCHAR(256),
				TYPE				VARCHAR(256),
				CONTROL_URL			VARCHAR(512),
				EVENT_URL			VARCHAR(512),
				SCPD_URL			VARCHAR(512)
			);"
		);
	}

	unless (grep(/^STAT_MEM$/, @tables))
	{
		$dbh->do("CREATE TABLE STAT_MEM (
				DATE				BIGINT PRIMARY KEY,
				VMS					BIGINT,
				RSS					BIGINT
			);"
		);
	}

	unless (grep(/^STAT_ITEMS$/, @tables))
	{
		$dbh->do("CREATE TABLE STAT_ITEMS (
				DATE				BIGINT PRIMARY KEY,
				AUDIO				INTEGER,
				AUDIO_SIZE			BIGINT,
				VIDEO				INTEGER,
				VIDEO_SIZE			BIGINT,
				IMAGE				INTEGER,
				IMAGE_SIZE			BIGINT
			);"
		);
	}

	PDLNA::Database::disconnect($dbh);
}

=item select_db_tables() - helper function to provide a list of database tables.


=cut

sub select_db_tables
{
	my $dbh = shift;

	my @tables = ();
	select_db_array(
		$dbh,
		{
			'query' => 'SELECT name FROM sqlite_master WHERE type = ?',
			'parameters' => [ 'table', ],
		},
		\@tables,
	);

	return @tables;
}

=item select_db_array() - execute a select query that returns an array.


=cut

sub select_db_array
{
	my $dbh = shift;
	my $params = shift;
	my $result = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');
	while (my $data = $sth->fetchrow_array())
	{
		push(@{$result}, $data);
	}
	PDLNA::Log::log('ERROR: Data fetching terminated early by error: '.$DBI::errstr, 0, 'database') if $DBI::err;

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
}

=item select_db_field_int() - execute a select query.


=cut

sub select_db_field_int
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');
	my $result = $sth->fetchrow_array();

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
	return $result || 0;
}

=item select_db() - execute a select query.


=cut

sub select_db
{
	my $dbh = shift;
	my $params = shift;
	my $result = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	#_log_query($params);
	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');
	while (my $data = $sth->fetchrow_hashref)
	{
		push(@{$result}, $data);
	}
	PDLNA::Log::log('ERROR: Data fetching terminated early by error: '.$DBI::errstr, 0, 'database') if $DBI::err;

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
}

=item insert_db() - execute an insert query.


=cut

sub insert_db
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
}

=item update_db() - execute an update query.


=cut

sub update_db
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
}

=item delete_db() - execute a delete query.


=cut

sub delete_db
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
}

#
# HELPER FUNCTIONS
#

=item log_query() - log the execution of a query.



=cut

sub _log_query
{
	my $params = shift;
	my $starttime = shift || 0;
	my $endtime = shift || 0;

	my $parameters = '';
	foreach my $param (@{$$params{'parameters'}})
	{
		if (defined($param))
		{
			$parameters .= $param.', ';
		}
		else
		{
			$parameters .= 'undefined, ';
		}
	}
	substr($parameters, -2) = '';

	my $time = $endtime - $starttime;

	PDLNA::Log::log('(Query took '.$time.'ms): '. $$params{'query'}.' - '.$parameters, 1, 'database');
}


=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010-2013 Stefan Heumader L<E<lt>stefan@heumader.atE<gt>>.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.

=cut


1;
