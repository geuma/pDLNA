package PDLNA::Config;
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
use Digest::MD5;
use Digest::SHA;
use File::Basename;
use File::MimeInfo;
use IO::Interface::Simple;
use Net::IP;
use Net::Netmask;
use Sys::Hostname qw(hostname);

use PDLNA::Media;

our %CONFIG = (
	# values which can be modified by configuration file
	'LOCAL_IPADDR' => undef,
	'LISTEN_INTERFACE' => undef,
	'HTTP_PORT' => 8001,
	'CACHE_CONTROL' => 1800,
	'PIDFILE' => '/var/run/pdlna.pid',
	'ALLOWED_CLIENTS' => [],
	'DB_TYPE' => 'SQLITE3',
	'DB_NAME' => '/tmp/pdlna.db',
	'DB_USER' => undef,
	'DB_PASS' => undef,
	'LOG_FILE_MAX_SIZE' => 10485760, # 10 MB
	'LOG_FILE' => 'STDERR',
	'LOG_CATEGORY' => [],
	'DATE_FORMAT' => '%Y-%m-%d %H:%M:%S',
	'BUFFER_SIZE' => 32768, # 32 kB
	'DEBUG' => 0,
	'SPECIFIC_VIEWS' => 0,
	'CHECK_UPDATES' => 1,
	'CHECK_UPDATES_NOTIFICATION' => 1,
	'ENABLE_GENERAL_STATISTICS' => 1,
	'RESCAN_MEDIA' => 86400,
	'UUID' => 'Version4',
	'TMP_DIR' => '/tmp',
	'IMAGE_THUMBNAILS' => 0,
	'VIDEO_THUMBNAILS' => 0,
	'LOW_RESOURCE_MODE' => 0,
	'MPLAYER_BIN' => '/usr/bin/mplayer',
	'FFMPEG_BIN' => '/usr/bin/ffmpeg',
	'DIRECTORIES' => [],
	'EXTERNALS' => [],
	'TRANSCODING_PROFILES' => [],
	# values which can be modified manually :P
	'PROGRAM_NAME' => 'pDLNA',
	'PROGRAM_VERSION' => '0.63.0',
	'PROGRAM_DATE' => '2013-07-08',
	'PROGRAM_BETA' => 0,
	'PROGRAM_DBVERSION' => '1.5',
	'PROGRAM_WEBSITE' => 'http://www.pdlna.com',
	'PROGRAM_AUTHOR' => 'Stefan Heumader',
	'PROGRAM_DESC' => 'Perl DLNA MediaServer',
	'AUTHOR_WEBSITE' => 'http://www.urandom.at',
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
$CONFIG{'FRIENDLY_NAME'} = 'pDLNA v'.print_version().' on '.$CONFIG{'HOSTNAME'};

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
		valid_blocks => [qw(Directory External Transcode)],
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
	my @interfaces = IO::Interface::Simple->interfaces();
	if ($cfg->get('ListenInterface'))
	{
		$CONFIG{'LISTEN_INTERFACE'} = $cfg->get('ListenInterface');
	}
	# Get the first non lo interface
	else
	{
		foreach my $interface (@interfaces)
		{
			next if $interface =~ /^lo/i;
			next unless $interface->address();
			$CONFIG{'LISTEN_INTERFACE'} = $interface;
			last;
		}
	}

	if (grep(/^$CONFIG{'LISTEN_INTERFACE'}$/, @interfaces))
	{
		my $interface = IO::Interface::Simple->new($CONFIG{'LISTEN_INTERFACE'});
		if ($cfg->get('ListenIPAddress'))
		{
			$CONFIG{'LOCAL_IPADDR'} = $cfg->get('ListenIPAddress');
			if ($CONFIG{'LOCAL_IPADDR'} ne $interface->address())
			{
				 push(@{$errormsg}, 'Invalid ListenInterface: The configured ListenIPAddress is not located on the configured ListenInterface '.$CONFIG{'LISTEN_INTERFACE'}.'.');
			}
		}
		else
		{
			$CONFIG{'LOCAL_IPADDR'} = $interface->address();
		}

		unless (Net::IP->new($CONFIG{'LOCAL_IPADDR'}))
		{
			push(@{$errormsg}, 'Invalid ListenIPAddress: '.Net::IP::Error().'.');
		}

		unless ($interface->is_multicast())
		{
			push(@{$errormsg}, 'Invalid ListenInterface: Interface is not capable of Multicast');
		}
	}
	else
	{
		 push (@{$errormsg}, 'Invalid ListenInterface: The configured interface does not exist on your machine.');
	}

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
		my $interface = IO::Interface::Simple->new($CONFIG{'LISTEN_INTERFACE'});
		if (defined($interface))
		{
			push(@{$CONFIG{'ALLOWED_CLIENTS'}}, Net::Netmask->new($CONFIG{'LOCAL_IPADDR'}.'/'.$interface->netmask()));
		}
		else
		{
			push(@{$errormsg}, 'Unable to autodetect AllowedClient configuration parameter. Please specify it in the configuration file.');
		}
	}

	#
	# DATABASE PARSING
	#
	$CONFIG{'DB_TYPE'} = $cfg->get('DatabaseType') if defined($cfg->get('DatabaseType'));
	unless ($CONFIG{'DB_TYPE'} eq 'SQLITE3')
	{
		push(@{$errormsg}, 'Invalid DatabaseType: Available options [SQLITE3]');
	}

	if ($CONFIG{'DB_TYPE'} eq 'SQLITE3')
	{
		$CONFIG{'DB_NAME'} = $cfg->get('DatabaseName') if defined($cfg->get('DatabaseName'));
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
	# TODO parsing and defining them in configuration file - for MySQL and so on
#	$CONFIG{'DB_USER'} = $cfg->get('DatabaseUsername') if defined($cfg->get('DatabaseUsername'));
#	$CONFIG{'DB_PASS'} = $cfg->get('DatabasePassword') if defined($cfg->get('DatabasePassword'));

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
			unless ($category =~ /^(discovery|httpdir|httpstream|library|httpgeneric|database|transcoding|soap)$/)
			{
				push(@{$errormsg}, 'Invalid LogCategory: Available options [discovery|httpdir|httpstream|library|httpgeneric|database|transcoding|soap]');
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
	# CHECK FOR UPDATES
	#
	$CONFIG{'CHECK_UPDATES'} = eval_binary_value($cfg->get('Check4Updates')) if defined($cfg->get('Check4Updates'));

	#
	# CHECK_UPDATES_NOTIFICATION
	#
	$CONFIG{'CHECK_UPDATES_NOTIFICATION'} = eval_binary_value($cfg->get('Check4UpdatesNotification')) if defined($cfg->get('Check4UpdatesNotification'));

	#
	# ENABLE_GENERAL_STATISTICS
	#
	$CONFIG{'ENABLE_GENERAL_STATISTICS'} = eval_binary_value($cfg->get('EnableGeneralStatistics')) if defined($cfg->get('EnableGeneralStatistics'));

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
	# LowResourceMode
	#
	$CONFIG{'LOW_RESOURCE_MODE'} = eval_binary_value($cfg->get('LowResourceMode')) if defined($cfg->get('LowResourceMode'));

	#
	# MPlayerBinaryPath
	#
	$CONFIG{'MPLAYER_BIN'} = $cfg->get('MPlayerBinaryPath') if defined($cfg->get('MPlayerBinaryPath'));
	if ($CONFIG{'LOW_RESOURCE_MODE'} == 0 || $CONFIG{'VIDEO_THUMBNAILS'} == 1) # only check for mplayer installation if LOW_RESOURCE_MODE is disabled and VIDEO_THUMBNAILS is enabled
	{
		if (-x $CONFIG{'MPLAYER_BIN'})
		{
			open(CMD, $CONFIG{'MPLAYER_BIN'}.' --help |');
			my @output = <CMD>;
			close(CMD);

			my $found = 0;
			foreach my $line (@output)
			{
				$found = 1 if $line =~ /^MPlayer\s+(.+)\s+\(/;
			}

			unless ($found)
			{
				push(@{$errormsg}, 'Invalid MPlayer Binary: Unable to detect MPlayer installation.');
			}
		}
		else
		{
			push(@{$errormsg}, 'Invalid path for MPlayer Binary: Please specify the correct path or install MPlayer.');
		}
	}

	#
	# FFmpegBinaryPath
	#
	$CONFIG{'FFMPEG_BIN'} = $cfg->get('FFmpegBinaryPath') if defined($cfg->get('FFmpegBinaryPath'));
	my $ffmpeg_error_message = undef;
	if (-x $CONFIG{'FFMPEG_BIN'})
	{
		unless (PDLNA::Transcode::get_ffmpeg_codecs($CONFIG{'FFMPEG_BIN'}, $CONFIG{'AUDIO_CODECS_DECODE'}, $CONFIG{'AUDIO_CODECS_ENCODE'}, $CONFIG{'VIDEO_CODECS_DECODE'}, $CONFIG{'VIDEO_CODECS_ENCODE'}))
		{
			$ffmpeg_error_message = 'Invalid FFmpeg Binary: Unable to detect FFmpeg installation.';
		}
		unless (PDLNA::Transcode::get_ffmpeg_formats($CONFIG{'FFMPEG_BIN'}, $CONFIG{'FORMATS_DECODE'}, $CONFIG{'FORMATS_ENCODE'}))
		{
			$ffmpeg_error_message = 'Invalid FFmpeg Binary: Unable to detect FFmpeg installation.';
		}
	}
	else
	{
		$ffmpeg_error_message = 'Invalid path for FFmpeg Binary: Please specify the correct path or install FFmpeg.';
	}

	#
	# UUID
	#
	# some of the marked code lines are taken from UUID::Tiny perl module,
	# which is not working
	# IMPORTANT NOTE: NOT compliant to RFC 4122
	my $mac = undef;
	$CONFIG{'UUID'} = $cfg->get('UUID') if defined($cfg->get('UUID'));
	if ($CONFIG{'UUID'} eq 'Version3')
	{
		my $md5 = Digest::MD5->new;
		$md5->add($CONFIG{'HOSTNAME'});
		$CONFIG{'UUID'} = substr($md5->digest(), 0, 16);
		$CONFIG{'UUID'} = join '-', map { unpack 'H*', $_ } map { substr $CONFIG{'UUID'}, 0, $_, '' } ( 4, 2, 2, 2, 6 ); # taken from UUID::Tiny perl module
	}
	elsif ($CONFIG{'UUID'} eq 'Version4' || $CONFIG{'UUID'} eq 'Version4MAC')
	{
		if ($CONFIG{'UUID'} eq 'Version4MAC') # determine the MAC address of our listening interfae
		{
			my $interface = IO::Interface::Simple->new($CONFIG{'LISTEN_INTERFACE'});
			$mac = lc($interface->hwaddr());
		}

		my @chars = qw(a b c d e f 0 1 2 3 4 5 6 7 8 9);
		$CONFIG{'UUID'} = '';
		while (length($CONFIG{'UUID'}) < 36)
		{
			$CONFIG{'UUID'} .= $chars[int(rand(@chars))];
			$CONFIG{'UUID'} .= '-' if length($CONFIG{'UUID'}) =~ /^(8|13|18|23)$/;
		}

		if (defined($mac))
		{
			$mac =~ s/://g;
			$CONFIG{'UUID'} = substr($CONFIG{'UUID'}, 0, 24).$mac;
		}
	}
	elsif ($CONFIG{'UUID'} eq 'Version5')
	{
		my $sha = Digest::SHA->new();
		$sha->add($CONFIG{'HOSTNAME'});
		$CONFIG{'UUID'} = substr($sha->digest(), 0, 16);
		$CONFIG{'UUID'} = join '-', map { unpack 'H*', $_ } map { substr $CONFIG{'UUID'}, 0, $_, '' } ( 4, 2, 2, 2, 6 ); # taken from UUID::Tiny perl module
	}
	elsif ($CONFIG{'UUID'} =~ /^[0-9a-f]{8}\-[0-9a-f]{4}\-[0-9a-f]{4}\-[0-9a-f]{4}\-[0-9a-f]{12}$/i)
	{
	}
	else
	{
		push(@{$errormsg}, 'Invalid type for UUID: Available options [Version3|Version4|Version4MAC|Version5|<staticUUID>]');
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
	if ($CONFIG{'LOW_RESOURCE_MODE'} == 0) # ignore External configured media when LowResourceMode is enabled
	{
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
				unless (PDLNA::Media::is_supported_stream($external{'streamurl'}))
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
	}

	#
	# TRANSCODING PROFILES
	#
	if ($CONFIG{'LOW_RESOURCE_MODE'} == 0) # ignore Transcoding when LowResourceMode is enabled
	{
		foreach my $transcode_block ($cfg->get('Transcode'))
		{
			if (defined($ffmpeg_error_message))
			{
				push(@{$errormsg}, $ffmpeg_error_message);
				last;
			}

			my $block = $cfg->block(Transcode => $transcode_block->[1]);
			my %transcode = (
				'Name' => $transcode_block->[1],
			);
			my $transcode_error_msg = 'Invalid Transcoding Profile \''.$transcode_block->[1].'\': ';

			if (defined($block->get('MediaType')) && $block->get('MediaType') =~ /^(audio)$/)
			{
				$transcode{'MediaType'} = $block->get('MediaType');
			}
			else
			{
				push(@{$errormsg}, $transcode_error_msg.'Invalid MediaType.');
			}

			my @types = ('AudioCodec');
			foreach my $type (@types)
			{
				foreach my $direction ('In', 'Out')
				{
					# since $block->get returns 1 if keyword is defined
					unless (defined($block->get($type.$direction)) && $block->get($type.$direction) ne '1')
					{
						push(@{$errormsg}, $transcode_error_msg.$type.$direction.' is not defined.');
						next;
					}

					if ($type eq 'AudioCodec')
					{
						#
						# CHECK IF FFMPEG SUPPORTS THE CHOSEN CODECS
						#
						my $ffmpeg_codec = undef;
						$ffmpeg_codec = PDLNA::Transcode::is_supported_audio_decode_codec(lc($block->get($type.$direction))) if $direction eq 'In';
						$ffmpeg_codec = PDLNA::Transcode::is_supported_audio_encode_codec(lc($block->get($type.$direction))) if $direction eq 'Out';
						if (defined($ffmpeg_codec))
						{
							my $tmp_string = 'AUDIO_CODECS_DECODE';
							$tmp_string = 'AUDIO_CODECS_ENCODE' if $direction eq 'Out';

							if (grep/^$ffmpeg_codec$/, @{$CONFIG{$tmp_string}})
							{
								$transcode{$type.$direction} = lc($block->get($type.$direction));
							}
							else
							{
								my $tmp_msg = $transcode_error_msg.$type.$direction.' '.$block->get($type.$direction).' ';
								$tmp_msg .= 'for transcoding is NOT supported by your FFmpeg installation';
								push(@{$errormsg}, $tmp_msg);
							}
						}
						else
						{
							my $tmp_msg = $transcode_error_msg.$block->get($type.$direction);
							$tmp_msg .= ' is not a supported '.$type.' for '.$type.$direction.' yet.';
							push(@{$errormsg}, $tmp_msg);
						}

						#
						# CHECK IF FFMPEG SUPPORTS THE FORMATS
						#
						my $format = undef;
						$format = PDLNA::Transcode::get_decode_format_by_audio_codec(lc($block->get($type.$direction))) if $direction eq 'In';
						$format = PDLNA::Transcode::get_encode_format_by_audio_codec(lc($block->get($type.$direction))) if $direction eq 'Out';

						if (defined($format))
						{
							my $tmp_string = 'FORMATS_DECODE';
							$tmp_string = 'FORMATS_ENCODE' if $direction eq 'Out';

							unless (grep(/^$format$/, @{$CONFIG{$tmp_string}}))
							{
								my $tmp_msg = $transcode_error_msg;
								$tmp_msg .= 'Decode' if $direction eq 'In';
								$tmp_msg .= 'Encode' if $direction eq 'Out';
								$tmp_msg .= 'Format '.$format.' for transcoding of ';
								$tmp_msg .= $block->get($type.$direction).' is NOT supported by your FFmpeg installation';
								push(@{$errormsg}, $tmp_msg);
							}
						}
						else
						{
							my $tmp_msg = $transcode_error_msg;
							$tmp_msg .= 'Decode' if $direction eq 'In';
							$tmp_msg .= 'Encode' if $direction eq 'Out';
							$tmp_msg .= 'Format of '.$type.$direction.' is not supported yet.';
							push(@{$errormsg}, $tmp_msg);
						}
					}
				}
			}

			my @clients = ();
			if (defined($block->get('ClientIPs')) && $block->get('ClientIPs') ne '1')
			{
				foreach my $ip_subnet (split(/\s*,\s*/, $block->get('ClientIPs')))
				{
					# We still need to use Net::IP as it validates that the ip/subnet is valid
					if (Net::IP->new($ip_subnet))
					{
						push(@clients, Net::Netmask->new($ip_subnet));
					}
					else
					{
						push(@{$errormsg}, 'Invalid Transcoding Profile \''.$transcode_block->[1].'\': '.Net::IP::Error().'.');
					}
				}
			}
			else
			{
				push(@{$errormsg}, 'Invalid Transcoding Profile \''.$transcode_block->[1].'\': Please configure ClientIPs.');
			}
			$transcode{'ClientIPs'} = \@clients;

			push(@{$CONFIG{'TRANSCODING_PROFILES'}}, \%transcode);
		}
	}

	return 1 if (scalar(@{$errormsg}) == 0);
	return 0;
}

1;
