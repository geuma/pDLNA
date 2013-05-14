package PDLNA::Database;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2013 Stefan Heumader <stefan@heumader.at>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

use DBI;

use PDLNA::Config;
use PDLNA::Log;

sub connect
{
	my $dbh = undef;
	if ($CONFIG{'DB_TYPE'} eq 'SQLITE3')
	{
		$dbh = DBI->connect('dbi:SQLite:dbname='.$CONFIG{'DB_NAME'},'','') || PDLNA::Log::fatal('Cannot connect: '.$DBI::errstr);
	}
	return $dbh;
}

sub disconnect
{
	my $dbh = shift;
	$dbh->disconnect();
}

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
				ID				INTEGER PRIMARY KEY AUTOINCREMENT,

				NAME				VARCHAR(2048),
				PATH				VARCHAR(2048),
				FULLNAME			VARCHAR(2048),
				FILE_EXTENSION			VARCHAR(4),

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
				VBR				BOOLEAN,

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
				ID				INTEGER PRIMARY KEY AUTOINCREMENT,

				IP				VARCHAR(15),
				USER_AGENT			VARCHAR(128),
				LAST_SEEN			BIGINT
			);"
		);
	}

	unless (grep(/^DEVICE_BM$/, @tables))
	{
		$dbh->do("CREATE TABLE DEVICE_BM (
				ID				INTEGER PRIMARY KEY AUTOINCREMENT,
				DEVICE_IP_REF			INTEGER,

				FILE_ID_REF			INTEGER,
				POS_SECONDS			INTEGER
			);"
		);
	}

	unless (grep(/^DEVICE_UDN$/, @tables))
	{
		$dbh->do("CREATE TABLE DEVICE_UDN (
				ID				INTEGER PRIMARY KEY AUTOINCREMENT,
				DEVICE_IP_REF			INTEGER,

				UDN				VARCHAR(64),
				SSDP_BANNER			VARCHAR(256),
				DESC_URL			VARCHAR(512),
				RELA_URL			VARCHAR(512),
				BASE_URL			VARCHAR(512),

				TYPE				VARCHAR(256),
				MODEL_NAME			VARCHAR(256),
				FRIENDLY_NAME			VARCHAR(256)
			);"
		);
	}

	unless (grep(/^DEVICE_NTS$/, @tables))
	{
		$dbh->do("CREATE TABLE DEVICE_NTS (
				ID				INTEGER PRIMARY KEY AUTOINCREMENT,
				DEVICE_UDN_REF			INTEGER,

				TYPE				VARCHAR(128),
				EXPIRE				BIGINT
			);"
		);
	}

	unless (grep(/^DEVICE_SERVICE$/, @tables))
	{
		$dbh->do("CREATE TABLE DEVICE_SERVICE (
				ID				INTEGER PRIMARY KEY AUTOINCREMENT,
				DEVICE_UDN_REF			INTEGER,

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
				VMS				BIGINT,
				RSS				BIGINT
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

sub select_db_array
{
	my $dbh = shift;
	my $params = shift;
	my $result = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}}) or die $sth->errstr;
	while (my $data = $sth->fetchrow_array())
	{
		push(@{$result}, $data);
	}

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
}

sub select_db_field_int
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}}) or die $sth->errstr;
	my $result = $sth->fetchrow_array();

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
	return $result || 0;
}

sub select_db
{
	my $dbh = shift;
	my $params = shift;
	my $result = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	#_log_query($params);
	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}}) or die $sth->errstr;
	while (my $data = $sth->fetchrow_hashref)
	{
		push(@{$result}, $data);
	}

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
}

sub insert_db
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}}) or die $sth->errstr;

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
}

sub update_db
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}}) or die $sth->errstr;;

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
}

sub delete_db
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}}) or die $sth->errstr;;

	_log_query($params, $starttime, PDLNA::Utils::get_timestamp_ms());
}

#
# HELPER FUNCTIONS
#

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


#
# STATS
# 
sub insert_stats_proc
{
 my $time = shift;
 my $vmsize = shift;
 my $rssize = shift; 
 

   my $dbh = PDLNA::Database::connect();           
   PDLNA::Database::insert_db(
                $dbh,
                {'query' => 'INSERT INTO STAT_MEM (DATE, VMS, RSS) VALUES (?,?,?)',
                'parameters' => [ $time, $vmsize, $rssize, ]}               
	        );
   PDLNA::Database::disconnect($dbh);	        
}                                                                                                                                                                                        



sub insert_stats_media
{ 
 my $time = shift;
 my $audio_amount = shift;
 my $audio_size   = shift;
 my $image_amount = shift;
 my $image_size   = shift;
 my $video_amount = shift;
 my $video_size   = shift;
 
   my $dbh = PDLNA::Database::connect();
   PDLNA::Database::insert_db(
                   $dbh,
                   {'query' => 'INSERT INTO STAT_ITEMS (DATE, AUDIO, AUDIO_SIZE, IMAGE, IMAGE_SIZE, VIDEO, VIDEO_SIZE) VALUES (?,?,?,?,?,?,?)', 
                    'parameters' => [ $time, $audio_amount, $audio_size, $image_amount, $image_size, $video_amount, $video_size, ], 
                   },
                  );
   PDLNA::Database::disconnect($dbh);
                        
}


sub stats_getdata
{
 my $dateformatstring = shift;
 my $dbtable          = shift;
 my $period           = shift;
 my @dbfields         = @_;

        my @results = ();
        my $dbh = PDLNA::Database::connect();
        PDLNA::Database::select_db(
              $dbh,
               {
                'query' =>  "SELECT strftime('".$dateformatstring."',datetime(DATE, 'unixepoch', 'localtime')) AS datetime,
                                     " .join(', ', @dbfields).  "
                              FROM ".$dbtable. " 
                              WHERE DATE > strftime('%s', 'now', 'start of ".$period."', 'utc') 
                              GROUP BY datetime",
                        'parameters' => [ ]
                },
                \@results,
        );
        PDLNA::Database::disconnect($dbh);
    return @results;
}

##
## FILES
##
sub get_amount_size_of_items
{
  my $type = shift || undef;


        my $dbh = PDLNA::Database::connect();


        my $sql_query = 'SELECT COUNT(ID) AS AMOUNT, SUM(SIZE) AS SIZE FROM FILES';
        my @sql_param = ();
        if (defined($type))
        {
                $sql_query .= ' WHERE TYPE = ? GROUP BY TYPE';
                push(@sql_param, $type);
        }

        my @result = ();
        PDLNA::Database::select_db(
                $dbh,
                {
                        'query' => $sql_query,
                        'parameters' => \@sql_param,
                },
                \@result,
        );

        PDLNA::Database::disconnect($dbh);

        return ($result[0]->{AMOUNT}, $result[0]->{SIZE});
}

##
## DEVICE_IP

sub  device_ip_select_all
{
        my @devices_ip = ();
        my $dbh = PDLNA::Database::connect();
        PDLNA::Database::select_db(
                $dbh,
                {
                        'query' => 'SELECT ID, IP FROM DEVICE_IP',
                        'parameters' => [ ],
                },
                \@devices_ip,
        );
        PDLNA::Database::disconnect($dbh);

    return @devices_ip;

}

sub device_ip_delete_by_id
 {
  my $device_ip_id = shift;

        my $dbh = PDLNA::Database::connect();
        PDLNA::Database::delete_db(
                $dbh,
                {
                 'query' => 'DELETE FROM DEVICE_IP WHERE ID = ?',
                 'parameters' => [ $device_ip_id, ],
                },
        );
       PDLNA::Database::disconnect($dbh);
}

#
# given a database connection and a ip address,
# returns its id

sub device_ip_get_id
{
   my $dbh = shift;
   my $ip = shift;
        
        my $flag = 0;
        if (!defined $ip)              # We only pass one param 
        {                              # when we want this function to make
         $ip = $dbh;                   # its own database connection 
         $dbh = PDLNA::Database::connect();
         $flag = 1;
        }
        
        my @devices = ();
        PDLNA::Database::select_db(
                       $dbh,
                       {
                        'query' => 'SELECT ID, IP, USER_AGENT, LAST_SEEN  FROM DEVICE_IP WHERE IP = ?',
                        'parameters' => [ $ip, ],
                       },
                      \@devices,
                     );
                     
        PDLNA::Database::disconnect($dbh) if $flag;
        return $devices[0];
}


#
# If a new IP address is presented, it updates the last_seen and user agent 
# if possible, if the ip is new, then a new device_ip address is created.
sub  device_ip_touch
{
  my $ip = shift;
  my $useragent = shift;

  my $sql;
  my $params;
  my @result;

        my $dbh = PDLNA::Database::connect();
        my $time = time ();

        my $device_ip =  PDLNA::Database::device_ip_get_id($dbh,$ip); 
        if (!defined($device_ip)) 
         {
           PDLNA::Database::insert_db(
                        $dbh,
                        {
                           'query' => 'INSERT INTO DEVICE_IP (IP) VALUES (?)',
                           'parameters' => [ $ip ],
                        },
                );
           $device_ip =  PDLNA::Database::device_ip_get_id($dbh,$ip); 
         }

        if (defined($useragent)) 
         {
          $sql = 'UPDATE DEVICE_IP SET LAST_SEEN = ?, USER_AGENT = ? WHERE ID = ?';
          $params = [ $time,$useragent,$device_ip->{ID} ];
         }
        else
         {
          $sql = 'UPDATE DEVICE_IP SET LAST_SEEN = ?  WHERE ID = ?';
          $params = [ $time,$device_ip->{ID} ];
         }

         PDLNA::Database::update_db(
                     $dbh,
                       {
                        'query' => $sql, 
                        'parameters' => $params
                        },
                );

         PDLNA::Database::disconnect($dbh);
         
         return $device_ip->{ID};
}

##
## DEVICE UDN

sub device_udn_get_record
{
   my $device_ip_id = shift;
      
              my $dbh = PDLNA::Database::connect();
              my @devices_udn = ();

             PDLNA::Database::select_db(
                        $dbh,
                        {
                         'query' => 'SELECT ID, UDN, SSDP_BANNER, FRIENDLY_NAME, MODEL_NAME, TYPE, DESC_URL FROM DEVICE_UDN WHERE ID = ?', 
                         'parameters' => [ $device_ip_id ],
                        },
               \@devices_udn
              );
             PDLNA::Database::disconnect($dbh);
             return $devices_udn[0];                                               
}



sub device_udn_get_id
{
  my $device_ip_id = shift;
  my $device_udn = shift;


        my $dbh = PDLNA::Database::connect();
        my @device_udn = ();

        PDLNA::Database::select_db(
                $dbh,
                {
                 'query' => 'SELECT ID FROM DEVICE_UDN WHERE DEVICE_IP_REF = ? AND UDN = ?',
                 'parameters' => [ $device_ip_id, $device_udn, ],
                },
                \@device_udn,
        );


        PDLNA::Database::disconnect($dbh);
        return $device_udn[0]->{ID};
}


sub device_udn_insert
{
  my $device_ip_id = shift;
  my $udn          = shift;
  my $ssdp_banner  = shift;
  my $dev_desc_loc = shift;
  my $dev_udn_base_url = shift;
  my $dev_udn_rela_url = shift;
  my $dev_udn_devicetype = shift;
  my $dev_udn_modelname  = shift;
  my $dev_udn_friendlyname = shift;

        my $dbh = PDLNA::Database::connect();
        PDLNA::Database::insert_db(
                 $dbh,
                  {
           'query' => 'INSERT INTO DEVICE_UDN (DEVICE_IP_REF, UDN, SSDP_BANNER, DESC_URL, RELA_URL, BASE_URL, TYPE, MODEL_NAME, FRIENDLY_NAME) VALUES (?,?,?,?,?,?,?,?,?)',
           'parameters' => [ $device_ip_id, $udn, $ssdp_banner, $dev_desc_loc, $dev_udn_base_url, $dev_udn_rela_url, $dev_udn_devicetype, $dev_udn_modelname, $dev_udn_friendlyname, ],
                   },
         );
        PDLNA::Database::disconnect($dbh);

}


sub device_udn_get_modelname
{ 
  my $ip = shift;

        my @modelnames = ();
        my $dbh = PDLNA::Database::connect();
        PDLNA::Database::select_db(
                $dbh,
                {
                  'query' => 'SELECT ID, MODEL_NAME FROM DEVICE_UDN WHERE DEVICE_IP_REF IN (SELECT ID FROM DEVICE_IP WHERE IP = ?)',
                  'parameters' => [ $ip, ],
                },
                \@modelnames,
        );
        PDLNA::Database::disconnect($dbh);
        return @modelnames;
}

sub device_udn_delete_by_id
{
  my $dbh = shift;
  my $device_udn_id = shift;

        my $flag = 0;
        if (!defined $device_udn_id)   # We only pass one param 
        {                              # when we want this function to make
         $device_udn_id = $dbh;        # its own database connection 
         $dbh = PDLNA::Database::connect();
         $flag = 1;
        }

        PDLNA::Database::delete_db(
                $dbh,
                {
                        'query' => 'DELETE FROM DEVICE_UDN WHERE ID = ?',
                        'parameters' => [ $device_udn_id, ],
                },
        );

        # delete the DEVICE_SERVICE entries
        PDLNA::Database::device_service_delete($device_udn_id);
        
        PDLNA::Database::disconnect($dbh) if $flag;

}




sub device_udn_delete_without_nts
{

        my $dbh = PDLNA::Database::connect();
        my @device_udn = ();
        PDLNA::Database::select_db(
                $dbh,
                {
                 'query' => 'SELECT ID FROM DEVICE_UDN',
                 'parameters' => [ ],
                },
                \@device_udn,
        );
        foreach my $udn (@device_udn)
        {
                my @device_nts_amount = PDLNA::Database::device_nts_amount($udn->{ID});
                if ($device_nts_amount[0]->{AMOUNT} == 0)
                {
                       PDLNA::Database::device_udn_delete_by_id($dbh, $udn->{ID});
                }
        }
        PDLNA::Database::disconnect($dbh);

}


sub  device_udn_select_by_ip
{ 
  my $device_ip_id = shift;

                my @devices_udn = ();
                my $dbh = PDLNA::Database::connect();
                PDLNA::Database::select_db(
                        $dbh,
                        {
                                'query' => 'SELECT ID, UDN FROM DEVICE_UDN WHERE DEVICE_IP_REF = ?',
                                'parameters' => [ $device_ip_id ],
                        },
                        \@devices_udn,
                );
                PDLNA::Database::disconnect($dbh);

       return @devices_udn;
}


##
## DEVICE SERVICE
##
sub device_service_insert
{
  my $device_udn_id = shift;
  my $serviceId     = shift;
  my $serviceType   = shift;
  my $controlURL    = shift;
  my $eventSubURL   = shift;
  my $scpdURL       = shift;

        my $dbh = PDLNA::Database::connect();
        PDLNA::Database::insert_db(
           $dbh,
            {
            'query' => 'INSERT INTO DEVICE_SERVICE (DEVICE_UDN_REF, SERVICE_ID, TYPE, CONTROL_URL, EVENT_URL, SCPD_URL) VALUES (?,?,?,?,?,?)',
            'parameters' => [ $device_udn_id, $serviceId, $serviceType, $controlURL, $eventSubURL, $scpdURL ],
             }
        );
       PDLNA::Database::disconnect($dbh);

}


sub device_service_delete
{
   my $dbh           = shift;
   my $device_udn_id = shift;
      
      
             my $flag = 0;
             if (!defined $device_udn_id)       # We only pass one param 
             {                                  # when we want this function to make
              $device_udn_id = $dbh;            # its own database connection
              $dbh = PDLNA::Database::connect();
              $flag = 1;
             }
            PDLNA::Database::delete_db(
            $dbh, 
               {
                    'query' => 'DELETE FROM DEVICE_SERVICE WHERE DEVICE_UDN_REF = ?',
                        'parameters' => [ $device_udn_id, ],
               },
            );
            PDLNA::Database::disconnect($dbh) if $flag;

}

  

##
## DEVICE NTS
##

sub  device_nts_amount
{
 my $dbh           = shift;
 my $device_udn_id = shift;


        my $flag = 0;
        if (!defined $device_udn_id)   # We only pass one param 
        {                              # when we want this function to make
         $device_udn_id = $dbh;        # its own database connection 
         $dbh = PDLNA::Database::connect();
         $flag = 1;
        }

         my @device_nts_amount = ();
         PDLNA::Database::select_db(
               $dbh,
               {
                'query' => 'SELECT COUNT(ID) AS AMOUNT FROM DEVICE_NTS WHERE DEVICE_UDN_REF = ?',
                'parameters' => [ $device_udn_id ],
                },
               \@device_nts_amount,
         );
         PDLNA::Database::disconnect($dbh) if ($flag);
         return @device_nts_amount;

}


sub device_nts_get_records
{
 my $device_udn_ref = shift;

                my $dbh = PDLNA::Database::connect();

                my @device_nts = ();
                PDLNA::Database::select_db(
                        $dbh,
                        {
                         'query' => 'SELECT TYPE, EXPIRE FROM DEVICE_NTS WHERE DEVICE_UDN_REF = ?',
                         'parameters' => [ $device_udn_ref ],
                        },
                       \@device_nts,
                );
                PDLNA::Database::disconnect($dbh);

          return @device_nts;
}


sub device_nts_device_udn_ref
{
  my $devicetype = shift;
 
                my @device_udns = (); 
                my $dbh = PDLNA::Database::connect();
                PDLNA::Database::select_db(
                        $dbh,
                        {
                                'query' => 'SELECT DEVICE_UDN_REF FROM DEVICE_NTS WHERE TYPE = ?',
                                'parameters' => [ $devicetype, ],
                        },
                        \@device_udns,
                );
                PDLNA::Database::disconnect($dbh);

                return @device_udns;
}



sub device_nts_get_id
{
   my $dbh = shift;
   my $device_udn_id = shift;  
   my $device_nts_type = shift;


        my $flag = 0;
        if (!defined $device_nts_type)        # We only pass one param 
        {                                     # when we want this function to make
         $device_nts_type = $device_udn_id;   # its own database connection
         $device_udn_id   = $dbh; 
         $dbh = PDLNA::Database::connect();
         $flag = 1;
        }

        my @device_nts = ();
        PDLNA::Database::select_db(
                $dbh,
                {
                        'query' => 'SELECT ID FROM DEVICE_NTS WHERE DEVICE_UDN_REF = ? AND TYPE = ?',
                        'parameters' => [ $device_udn_id, $device_nts_type, ],
                },
                \@device_nts,
        );
        PDLNA::Database::disconnect($dbh) if $flag;

        return $device_nts[0]->{ID};
}


sub device_nts_delete 
{
   my $dbh    = shift;
   my $nts_id = shift;


            my $flag = 0;
            if (!defined $nts_id)        # We only pass one param 
            {                                     # when we want this function to make
             $nts_id = $dbh;   # its own database connection
             $dbh = PDLNA::Database::connect();
             $flag = 1;
            }
                                                                    
            PDLNA::Database::delete_db(
            $dbh,
               {
                'query' => 'DELETE FROM DEVICE_NTS WHERE ID = ?',
                'parameters' => [ $nts_id ],
               },
            );
            PDLNA::Database::disconnect($dbh) if $flag;
}



sub device_nts_touch
{
 my $device_udn_id = shift;
 my $nt            = shift;
 my $nt_time_of_expire = shift;

        my $dbh = PDLNA::Database::connect();
        my $device_nts_id = PDLNA::Database::device_nts_get_id($dbh, $device_udn_id, $nt);
        if (defined($device_nts_id))
        {
                PDLNA::Database::update_db(
                        $dbh,
                        {
                                'query' => 'UPDATE DEVICE_NTS SET EXPIRE = ? WHERE ID = ? AND TYPE = ?',
                                'parameters' => [ $nt_time_of_expire, $device_nts_id, $nt ],
                        },
                );
        }
        else
        {
                PDLNA::Database::insert_db(
                        $dbh,
                        {
                                'query' => 'INSERT INTO DEVICE_NTS (DEVICE_UDN_REF, TYPE, EXPIRE) VALUES (?,?,?)',
                                'parameters' => [ $device_udn_id, $nt, $nt_time_of_expire ],
                        },
                );
                $device_nts_id = PDLNA::Database::device_nts_get_id($dbh, $device_udn_id, $nt);
        }
       PDLNA::Database::disconnect($dbh);
        
    return  $device_nts_id;
     
}


sub device_nts_delete_expired
{
  my @device_nts = ();

        my $time = time();
        my $dbh = PDLNA::Database::connect();
        PDLNA::Database::select_db(
                $dbh,
                {
                        'query' => 'SELECT ID, EXPIRE FROM DEVICE_NTS',
                        'parameters' => [ ],
                },
                \@device_nts,
        );
        foreach my $nts (@device_nts)
        {
                if ($nts->{EXPIRE} < $time)
                {
                  PDLNA::Database::device_nts_delete($dbh,$nts->{ID});
                }
        }
        PDLNA::Database::disconnect($dbh);

}
                 
##
## METADATA
sub metadata_get_vaue
{
  my $key = shift; 

                 my $dbh = PDLNA::Database::connect();
                 my $val = PDLNA::Database::select_db_field_int(
                     $dbh,
                        {
                        'query' => 'SELECT value FROM METADATA WHERE key = ?',
                        'parameters' => [ $key, ],
                        },
                 );
                 PDLNA::Database::disconnect($dbh);


    return $val;
}

##
## FILEINFO

sub fileinfo_get_all_sumduration
{
                my $dbh = PDLNA::Database::connect();
                my $duration = PDLNA::Database::select_db_field_int(
                        $dbh,
                        {
                                'query' => 'SELECT SUM(DURATION) AS SUMDURATION FROM FILEINFO',
                                'parameters' => [ ],
                        },
                );
               PDLNA::Database::disconnect($dbh);

  return $duration;
}

##
##
1;
