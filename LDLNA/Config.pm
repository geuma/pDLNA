package LDLNA::Config;
#

# Lombix DLNA - a perl DLNA media server
# Copyright (C) 2013 Cesar Lombao <lombao@lombix.com>
#
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

use base 'Exporter';

our @ISA = qw(Exporter);
our @EXPORT = qw(%CONFIG);




use Config qw();
use Config::ApacheFormat;
use File::Basename;
use File::MimeInfo;
use IO::Socket;
use IO::Interface qw(if_addr);
use Net::IP;
use Net::Netmask;
use Sys::Hostname qw(hostname);


our %CONFIG = (
	# values which can be modified by configuration file
	'LOCAL_IPADDR' => undef,
	'LISTEN_INTERFACE' => undef,
	'HTTP_PORT' => 8001,
	'CACHE_CONTROL' => 1800,
	'PIDFILE' => '/run/ldlna.pid',
	'ALLOWED_CLIENTS' => [],
	'DB_TYPE' => 'SQLITE3',
	'DB_NAME' => '/var/db/ldlna.db',
	'DB_USER' => undef,
	'DB_PASS' => undef,
	'LOG_FILE_MAX_SIZE' => 10485760, # 10 MB
	'LOG_FILE' => 'STDERR',
	'LOG_CATEGORY' => [],
	'DATE_FORMAT' => '%Y-%m-%d %H:%M:%S',
	'BUFFER_SIZE' => 32768, # 32 kB
	'DEBUG' => 0,
	'SPECIFIC_VIEWS' => 0,
	'RESCAN_MEDIA' => 86400,
	'TMP_DIR' => '/tmp',
	'IMAGE_THUMBNAILS' => 0,
	'VIDEO_THUMBNAILS' => 0,
	'LOW_RESOURCE_MODE' => 0,
	'FFMPEG_BIN' => '/usr/bin/ffmpeg',
        'RTMPDUMP_BIN' => '/usr/bin/rtmpdump',
        'UUIDGEN_BIN'  => '/usr/bin/uuidgen',
	'DIRECTORIES' => [],
	'EXTERNALS' => [],
	# values which can be modified manually :P
	'PROGRAM_NAME' => 'Lombix DLNA',
	'PROGRAM_VERSION' => '0.70.0',
	'PROGRAM_DATE' => '2013-xx-xx',
	'PROGRAM_BETA' => 1,
	'PROGRAM_DBVERSION' => '2.0',
	'PROGRAM_WEBSITE' => 'http://lombix.com',
	'PROGRAM_AUTHOR' => 'Cesar Lombao',
	'PROGRAM_DESC' => 'Perl DLNA MediaServer',
	'AUTHOR_WEBSITE' => 'http://lombix.com',
	'PROGRAM_SERIAL' => 1337,
	# arrays holding supported codec
	'AUDIO_CODECS_ENCODE' => [],
	'AUDIO_CODECS_DECODE' => [],
	'VIDEO_CODECS_ENCODE' => [],
	'VIDEO_CODECS_DECODE' => [],
	'FORMATS_ENCODE' => [],
	'FORMATS_DECODE' => [],
	'OS' => $Config::Config{osname},
	'OS_VERSION' => $Config::Config{osvers},
	'HOSTNAME' => hostname(),
);
$CONFIG{'FRIENDLY_NAME'} = 'Lombix DLNA v'.print_version().' on '.$CONFIG{'HOSTNAME'};

use LDLNA::Media;



sub print_version
{
	my $string = $CONFIG{'PROGRAM_VERSION'};
	$string .= 'b' if $CONFIG{'PROGRAM_BETA'};
	return $string;
}

sub eval_binary_value
{
	my $value = lc(shift);

	if ($value eq 'on' || $value eq 'true' || $value eq 'yes' || $value eq 'enable' || $value eq 'enabled' || $value eq '1')
	{
		return 1;
	}
	return 0;
}

sub parse_config
{
	my $file = shift;
	my $errormsg = shift;

	if (!-f $file)
	{
		push(@{$errormsg}, 'Configfile '.$file.' not found.');
		return 0;
	}

	my $cfg = Config::ApacheFormat->new(
		valid_blocks => [qw(Directory External)],
	);
	unless ($cfg->read($file))
	{
		push(@{$errormsg}, 'Configfile '.$file.' is not readable.');
		return 0;
	}

	#
	# FRIENDLY NAME PARSING
	#
	$CONFIG{'FRIENDLY_NAME'} = $cfg->get('FriendlyName') if defined($cfg->get('FriendlyName'));
	if ($CONFIG{'FRIENDLY_NAME'} !~ /^[\w\-\s\.]{1,32}$/)
	{
		push(@{$errormsg}, 'Invalid FriendlyName: Please use letters, numbers, dots, dashes, underscores and or spaces and the FriendlyName requires a name that is 32 characters or less in length.');
	}

	#
	# INTERFACE CONFIG PARSING
	#
	my $socket_obj = IO::Socket::INET->new(Proto => 'udp');
	if ($cfg->get('ListenInterface'))
	{
		$CONFIG{'LISTEN_INTERFACE'} = $cfg->get('ListenInterface');
	}
	# Get the first non lo interface
	else
	{
		foreach my $interface ($socket_obj->if_list)
		{
			next if $interface =~ /^lo/i;
			$CONFIG{'LISTEN_INTERFACE'} = $interface;
			last;
		}
	}

	push (@{$errormsg}, 'Invalid ListenInterface: The given interface does not exist on your machine.') if (!$socket_obj->if_flags($CONFIG{'LISTEN_INTERFACE'}));

	#
	# IP ADDR CONFIG PARSING
	#
	$CONFIG{'LOCAL_IPADDR'} = $cfg->get('ListenIPAddress') ? $cfg->get('ListenIPAddress') : $socket_obj->if_addr($CONFIG{'LISTEN_INTERFACE'});

	push(@{$errormsg}, 'Invalid ListenInterface: The given ListenIPAddress is not located on the given ListenInterface.') unless $CONFIG{'LISTEN_INTERFACE'} eq $socket_obj->addr_to_interface($CONFIG{'LOCAL_IPADDR'});

	#
	# HTTP PORT PARSING
	#
	$CONFIG{'HTTP_PORT'} = int($cfg->get('HTTPPort')) if defined($cfg->get('HTTPPort'));
	if ($CONFIG{'HTTP_PORT'} < 0 && $CONFIG{'HTTP_PORT'} > 65535)
	{
		push(@{$errormsg}, 'Invalid HTTPPort: Please specify a valid TCP port which is > 0 and < 65536.');
	}

	#
	# CHACHE CONTROL PARSING
	#
	$CONFIG{'CACHE_CONTROL'} = int($cfg->get('CacheControl')) if defined($cfg->get('CacheControl'));
	unless ($CONFIG{'CACHE_CONTROL'} > 60 && $CONFIG{'CACHE_CONTROL'} < 18000)
	{
		push(@{$errormsg}, 'Invalid CacheControl: Please specify the CacheControl in seconds (from 61 to 17999).');
	}

	#
	# PID FILE PARSING
	#
	$CONFIG{'PIDFILE'} = $cfg->get('PIDFile') if defined($cfg->get('PIDFile'));
	if (defined($CONFIG{'PIDFILE'}) && $CONFIG{'PIDFILE'} =~ /^\/[\w\.\_\-\/]+\w$/)
	{
		if (-e $CONFIG{'PIDFILE'})
		{
			push(@{$errormsg}, 'Warning PIDFile: The file named '.$CONFIG{'PIDFILE'}.' is already existing. Please change the filename or delete the file.');
		}
	}
	else
	{
		push(@{$errormsg}, 'Invalid PIDFile: Please specify a valid filename (full path) for the PID file.');
	}

	#
	# TMP DIRECTORY
	#
	$CONFIG{'TMP_DIR'} = $cfg->get('TempDir') if defined($cfg->get('TempDir'));
	unless (-d $CONFIG{'TMP_DIR'})
	{
		push(@{$errormsg}, 'Invalid TempDir: Directory '.$CONFIG{'TMP_DIR'}.' for temporary files is not existing.');
	}

	#
	# ALLOWED CLIENTS PARSING
	#
	if (defined($cfg->get('AllowedClients')))
	{
		# Store a list of Net::Netmask blocks that are valid for connections
		foreach my $ip_subnet (split(/\s*,\s*/, $cfg->get('AllowedClients')))
		{
			# We still need to use Net::IP as it validates that the ip/subnet is valid
			# Net::Netmask::new2 constructor also validates but I think is weird, so for
			# the time being I'll stick with Net::IP
			if (Net::IP->new($ip_subnet))
			{
				push(@{$CONFIG{'ALLOWED_CLIENTS'}}, Net::Netmask->new($ip_subnet));
			}
			else
			{
				push(@{$errormsg}, 'Invalid AllowedClient: '.Net::IP::Error().'.');
			}
		}
	}
	else # AllowedClients is not defined, so take the local subnet
	{
          push(@{$CONFIG{'ALLOWED_CLIENTS'}}, Net::Netmask->new($CONFIG{'LOCAL_IPADDR'}.'/'.( $socket_obj->if_netmask($CONFIG{'LISTEN_INTERFACE'})  ) ));
	}


	# TODO parsing and defining them in configuration file - for MySQL and so on
	$CONFIG{'DB_USER'} = $cfg->get('DatabaseUsername') if defined($cfg->get('DatabaseUsername'));
	$CONFIG{'DB_PASS'} = $cfg->get('DatabasePassword') if defined($cfg->get('DatabasePassword'));



	#
	# DATABASE PARSING
	#
    $CONFIG{'DB_NAME'} = $cfg->get('DatabaseName') if defined($cfg->get('DatabaseName'));
    
	$CONFIG{'DB_TYPE'} = $cfg->get('DatabaseType') if defined($cfg->get('DatabaseType'));
	unless (($CONFIG{'DB_TYPE'} eq 'SQLITE3') or ($CONFIG{'DB_TYPE'} eq 'PGSQL') or ($CONFIG{'DB_TYPE'} eq 'MYSQL'))
	{
		push(@{$errormsg}, 'Invalid DatabaseType: Available options [SQLITE3, PGSQL, MYSQL]');
	}

	if ($CONFIG{'DB_TYPE'} eq 'SQLITE3')
	{
		if (-f $CONFIG{'DB_NAME'})
		{
			unless (mimetype($CONFIG{'DB_NAME'}) eq 'application/octet-stream') # TODO better check if it is a valid database
			{
				push(@{$errormsg}, 'Invalid DatabaseName: Database '.$CONFIG{'DB_NAME'}.' is already existing but not a valid database.');
			}
		}
		else
		{
			unless (-d dirname($CONFIG{'DB_NAME'}))
			{
				push(@{$errormsg}, 'Invalid DatabaseName: Directory '.dirname($CONFIG{'DB_NAME'}).' for database is not existing.');
			}
		}
	}
	else # TODO, to verify in case is a PGSQL or MYSQL 
	{    # that the database ( using the DB_NAME DB_USER and DB_PASS ) is actually available
	}
	
	
	
	#
	# LOG FILE PARSING
	#
	$CONFIG{'LOG_FILE'} = $cfg->get('LogFile') if defined($cfg->get('LogFile'));
	unless ($CONFIG{'LOG_FILE'} eq 'STDERR' || $CONFIG{'LOG_FILE'} eq 'SYSLOG' || $CONFIG{'LOG_FILE'} =~ /^\/[\w\.\_\-\/]+\w$/)
	{
		push(@{$errormsg}, 'Invalid LogFile: Available options [STDERR|SYSLOG|<full path to LogFile>]');
	}

	#
	# LOG DATE FORMAT
	#
	$CONFIG{'DATE_FORMAT'} = $cfg->get('DateFormat') if defined($cfg->get('DateFormat'));
	unless ($CONFIG{'DATE_FORMAT'} =~ /^[\%mdHIMpsSoYZ\s\-\:\_\,]+$/)
	{
		push(@{$errormsg}, 'Invalid DateFormat: Valid characters are mdHIMpsSoYZ-:_,.% and spaces.');
	}

	#
	# LOG FILE SIZE MAX
	#
	if ($CONFIG{'LOG_FILE'} =~ /^\/[\w\.\_\-\/]+\w$/) # if a path to a file was specified
	{
		if (defined($cfg->get('LogFileMaxSize')))
		{
			$CONFIG{'LOG_FILE_MAX_SIZE'} = int($cfg->get('LogFileMaxSize'));
			unless ($CONFIG{'LOG_FILE_MAX_SIZE'} > 0 && $CONFIG{'LOG_FILE_MAX_SIZE'} < 100)
			{
				push(@{$errormsg}, 'Invalid LogFileMaxSize: Please specify LogFileMaxSize in megabytes (from 1 to 99).');
			}
			$CONFIG{'LOG_FILE_MAX_SIZE'} = $CONFIG{'LOG_FILE_MAX_SIZE'} * 1024 * 1024; # calc megabytes value from config file to bytes
		}
	}

	#
	# LOG CATEGORY
	#
	if (defined($cfg->get('LogCategory')))
	{
		@{$CONFIG{'LOG_CATEGORY'}} = split(',', $cfg->get('LogCategory'));
		foreach my $category (@{$CONFIG{'LOG_CATEGORY'}})
		{
			unless ($category =~ /^(discovery|httpdir|httpstream|library|httpgeneric|database|soap)$/)
			{
				push(@{$errormsg}, 'Invalid LogCategory: Available options [discovery|httpdir|httpstream|library|httpgeneric|database|soap]');
			}
		}
		push(@{$CONFIG{'LOG_CATEGORY'}}, 'default');
		push(@{$CONFIG{'LOG_CATEGORY'}}, 'update');
	}

	#
	# LOG LEVEL PARSING
	#
	$CONFIG{'DEBUG'} = int($cfg->get('LogLevel')) if defined($cfg->get('LogLevel'));
	if ($CONFIG{'DEBUG'} < 0)
	{
		push(@{$errormsg}, 'Invalid LogLevel: Please specify the LogLevel with a positive integer.');
	}

	#
	# BUFFER_SIZE
	#
	$CONFIG{'BUFFER_SIZE'} = int($cfg->get('BufferSize')) if defined($cfg->get('BufferSize'));

	#
	# SPECIFIC_VIEWS
	#
	$CONFIG{'SPECIFIC_VIEWS'} = eval_binary_value($cfg->get('SpecificViews')) if defined($cfg->get('SpecificViews'));

	

	#
	# RESCAN_MEDIA
	#
	if ($cfg->get('RescanMediaInterval'))
	{
		my %values = (
			'never' => 0,
			'hourly' => 3600,
			'halfdaily' => '43200',
			'daily' => 86400,
		);

		if (defined($values{$cfg->get('RescanMediaInterval')}))
		{
			$CONFIG{'RESCAN_MEDIA'} = $values{$cfg->get('RescanMediaInterval')};
		}
		else
		{
			push(@{$errormsg}, 'Invalid RescanMediaInterval:  Available options ['.join('|', keys %values).']');
		}
	}

	#
	# EnableImageThumbnails
	#
	$CONFIG{'IMAGE_THUMBNAILS'} = eval_binary_value($cfg->get('EnableImageThumbnails')) if defined($cfg->get('EnableImageThumbnails'));

	#
	# EnableVideoThumbnails
	#
	$CONFIG{'VIDEO_THUMBNAILS'} = eval_binary_value($cfg->get('EnableVideoThumbnails')) if defined($cfg->get('EnableVideoThumbnails'));

	#
	# FFmpegBinaryPath
	#
	$CONFIG{'FFMPEG_BIN'} = $cfg->get('FFmpegBinaryPath') if defined($cfg->get('FFmpegBinaryPath'));
	my $ffmpeg_error_message = undef;
	if (! -x $CONFIG{'FFMPEG_BIN'})
	{
		$ffmpeg_error_message = 'Invalid path for FFmpeg Binary: Please specify the correct path or install FFmpeg.';
	}

	#
	# UUID
	#
	# There is a lot to improve here. First of all I doubt this be portable, 
	#  second I have to implement some resilience and error checking
	my $mac = undef;
	open(CMD,"$CONFIG{UUIDGEN_BIN} 2>/dev/null|");
	 $CONFIG{'UUID'} = <CMD>;
	close(CMD);
	
         # This piece of code might not be portable and highly dependent on output from ip command.
	 # To be improved
	 open(CMD,"ip link show | grep ether |");
	 my $line = <CMD>; $line =~ / link\/ether ([\d|\w|:]+) /; $mac = $1;  
	 close(CMD);		   

	if (defined($mac))
 	 {
           $mac =~ s/://g;
	   $CONFIG{'UUID'} = substr($CONFIG{'UUID'}, 0, 24).$mac;	
	 }
        $CONFIG{'UUID'} = 'uuid:'.$CONFIG{'UUID'};

	#
	# MEDIA DIRECTORY PARSING
	#
	foreach my $directory_block ($cfg->get('Directory'))
	{
		my $block = $cfg->block(Directory => $directory_block->[1]);
		if (!-d $directory_block->[1])
		{
			push(@{$errormsg}, 'Invalid Directory \''.$directory_block->[1].'\': Not a directory.');
		}
		unless (defined($block->get('MediaType')) && $block->get('MediaType') =~ /^(audio|video|image|all)$/)
		{
			push(@{$errormsg}, 'Invalid Directory \''.$directory_block->[1].'\': Invalid MediaType.');
		}

		my $recursion = 'yes';
		if (defined($block->get('Recursion')))
		{
			if ($block->get('Recursion') !~ /^(no|yes)$/)
			{
				push(@{$errormsg}, 'Invalid Directory: \''.$directory_block->[1].'\': Invalid Recursion value.');
			}
			else
			{
				$recursion = $block->get('Recursion');
			}
		}

		my @exclude_dirs = ();
		if (defined($block->get('ExcludeDirs')))
		{
			@exclude_dirs = split(',', $block->get('ExcludeDirs'));
		}
		my @exclude_items = ();
		if (defined($block->get('ExcludeItems')))
		{
			@exclude_items = split(',', $block->get('ExcludeItems'));
		}

		my $allow_playlists = eval_binary_value($block->get('AllowPlaylists')) if defined($block->get('AllowPlaylists'));

		push(@{$CONFIG{'DIRECTORIES'}}, {
				'path' => $directory_block->[1],
				'type' => $block->get('MediaType'),
				'recursion' => $recursion,
				'exclude_dirs' => \@exclude_dirs,
				'exclude_items' => \@exclude_items,
				'allow_playlists' => $allow_playlists,
			}
		);
	}

    #
    # EXTERNAL SOURCES PARSING
    #
	    foreach my $external_block ($cfg->get('External'))
	    {
	        my $block = $cfg->block(External => $external_block->[1]);

			my %external = (
				'name' => $external_block->[1],
				'type' => '',
			);

			if (defined($block->get('StreamingURL')))
			{
				$external{'streamurl'} = $block->get('StreamingURL');
				unless (LDLNA::Media::is_supported_stream($external{'streamurl'}))
				{
					push(@{$errormsg}, 'Invalid External \''.$external_block->[1].'\': Not a valid streaming URL.');
				}
			}
			elsif (defined($block->get('Executable')))
			{
				if (-x $block->get('Executable'))
				{
					$external{'command'} = $block->get('Executable');
				}
				else
				{
					push(@{$errormsg}, 'Invalid External \''.$external_block->[1].'\': Script is not executable.');
				}

				if (defined($block->get('MediaType')) && $block->get('MediaType') =~ /^(audio|video)$/)
				{
					$external{'type'} = $block->get('MediaType');
				}
				else
				{
					push(@{$errormsg}, 'Invalid External \''.$external_block->[1].'\': Invalid MediaType.');
				}
			}
			else
			{
				push(@{$errormsg}, 'Invalid External \''.$external_block->[1].'\': Please define Executable or StreamingURL.');
			}
			push(@{$CONFIG{'EXTERNALS'}}, \%external);
    	    }

	return 1 if (scalar(@{$errormsg}) == 0);
	return 0;
}

sub get_ffmpeg
{
    return $CONFIG{'FFMPEG_BIN'};
}

sub get_rtmpdump
{
    return $CONFIG{'RTMPDUMP_BIN'};
}

1;
