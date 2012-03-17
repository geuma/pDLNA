package PDLNA::Config;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2012 Stefan Heumader <stefan@heumader.at>
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
use Digest::SHA1;
use IO::Socket;
use IO::Interface qw(if_addr);
use Net::Address::Ethernet qw(get_addresses);
use Net::Interface;
use Net::IP;
use Net::Netmask;
use Sys::Hostname qw(hostname);

our %CONFIG = (
	# values which can be modified by configuration file
	'LOCAL_IPADDR' => undef,
	'LISTEN_INTERFACE' => undef,
	'HTTP_PORT' => 8001,
	'CACHE_CONTROL' => 1800,
	'PIDFILE' => '/var/run/pdlna.pid',
	'ALLOWED_CLIENTS' => [],
	'LOG_FILE_MAX_SIZE' => 1048576, # 10 MB
	'LOG_FILE' => 'STDERR',
	'LOG_CATEGORY' => [],
	'DATE_FORMAT' => '%Y-%m-%d %H:%M:%S',
	'BUFFER_SIZE' => 32768, # 32 kB
	'DEBUG' => 0,
	'SPECIFIC_VIEWS' => 0,
	'CHECK_UPDATES' => 1,
	'UUID' => 'Version4',
	'TMP_DIR' => '/tmp',
	'IMAGE_THUMBNAILS' => 0,
	'VIDEO_THUMBNAILS' => 0,
	'MPLAYER_BIN' => '/usr/bin/mplayer',
	'FFMPEG_BIN' => '/usr/bin/ffmpeg',
	'DIRECTORIES' => [],
	'EXTERNALS' => [],
	'TRANSCODING_PROFILES' => [],
	# values which can be modified manually :P
	'PROGRAM_NAME' => 'pDLNA',
	'PROGRAM_VERSION' => '0.47.0',
	'PROGRAM_DATE' => '2012-03-xx',
	'PROGRAM_BETA' => 1,
	'PROGRAM_WEBSITE' => 'http://www.pdlna.com',
	'PROGRAM_AUTHOR' => 'Stefan Heumader',
	'PROGRAM_SERIAL' => 1337,
	'PROGRAM_DESC' => 'perl DLNA MediaServer',
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
		my $interface = Net::Interface->new($CONFIG{'LISTEN_INTERFACE'});
		push(@{$CONFIG{'ALLOWED_CLIENTS'}}, Net::Netmask->new($CONFIG{'LOCAL_IPADDR'}.'/'.inet_ntoa($interface->netmask())));
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
			unless ($category =~ /^(discovery|httpdir|httpstream|library|httpgeneric)$/)
			{
				push(@{$errormsg}, 'Invalid LogCategory: Available options [discovery|httpdir|httpstream|library|httpgeneric]');
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

	# TODO tmp directory

	#
	# EnableImageThumbnails
	#
	$CONFIG{'IMAGE_THUMBNAILS'} = eval_binary_value($cfg->get('EnableImageThumbnails')) if defined($cfg->get('EnableImageThumbnails'));

	#
	# EnableVideoThumbnails
	#
	$CONFIG{'VIDEO_THUMBNAILS'} = eval_binary_value($cfg->get('EnableVideoThumbnails')) if defined($cfg->get('EnableVideoThumbnails'));

	#
	# MPlayerBinaryPath
	#
	$CONFIG{'MPLAYER_BIN'} = $cfg->get('MPlayerBinaryPath') if defined($cfg->get('MPlayerBinaryPath'));
	# TODO check for x bit or even if it is mplayer
	unless (-f $CONFIG{'MPLAYER_BIN'})
	{
		push(@{$errormsg}, 'Invalid path for MPlayer Binary: Please specify the correct path or install MPlayer.');
	}

	#
	# FFmpegBinaryPath
	#
	$CONFIG{'FFMPEG_BIN'} = $cfg->get('FFmpegBinaryPath') if defined($cfg->get('FFmpegBinaryPath'));
	# TODO check for x bit or even if it is ffmpeg
	unless (-f $CONFIG{'FFMPEG_BIN'})
	{
		push(@{$errormsg}, 'Invalid path for FFmpeg Binary: Please specify the correct path or install FFmpeg.');
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
			my @addresses = get_addresses();
			foreach my $obj (@addresses)
			{
				$mac = lc($obj->{'sEthernet'}) if $obj->{'sAdapter'} eq $CONFIG{'LISTEN_INTERFACE'};
			}
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
		my $sha1 = Digest::SHA1->new;
		$sha1->add($CONFIG{'HOSTNAME'});
		$CONFIG{'UUID'} = substr($sha1->digest(), 0, 16);
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
    foreach my $external_block ($cfg->get('External'))
    {
        my $block = $cfg->block(External => $external_block->[1]);
		unless (defined($block->get('MediaType')) && $block->get('MediaType') =~ /^(audio|video)$/)
        {
            push(@{$errormsg}, 'Invalid External \''.$external_block->[1].'\': Invalid MediaType.');
        }

		my %external = (
			'name' => $external_block->[1],
			'type' => $block->get('MediaType'),
			'mimetype' => $block->get('MimeType'),
		);

		if (defined($block->get('StreamingURL')))
		{
			$external{'streamurl'} = $block->get('StreamingURL');
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
		}
		else
		{
			push(@{$errormsg}, 'Invalid External \''.$external_block->[1].'\': Please define Executable or StreamingURL.');
		}
		push(@{$CONFIG{'EXTERNALS'}}, \%external);
    }

	#
	# TRANSCODING PROFILES
	#
	my %audio_codecs = (
		'aac'	=> 'faad',
		'flac'	=> 'ffflac',
		'mp3'	=> 'mp3',
		'ogg'	=> 'ffvorbis',
		'wav'	=> 'pcm',
		'wmav2'	=> 'ffwmav2',
	);
	my %video_codecs = (
	);
	foreach my $transcode_block ($cfg->get('Transcode'))
	{
		my $block = $cfg->block(Transcode => $transcode_block->[1]);
        if (defined($block->get('MediaType')) && $block->get('MediaType') eq 'audio')
        {
			push(@{$errormsg}, 'Invalid Transcoding Profile \''.$transcode_block->[1].'\': '.$block->get('AudioIn').' is not a supported AudioCodec for AudioIn.') unless defined($audio_codecs{lc($block->get('AudioIn'))});
			push(@{$errormsg}, 'Invalid Transcoding Profile \''.$transcode_block->[1].'\': '.$block->get('AudioOut').' is not a supported AudioCodec for AudioOut.') unless defined($audio_codecs{lc($block->get('AudioOut'))});
			push(@{$errormsg}, 'Invalid Transcoding Profile \''.$transcode_block->[1].'\': '.$block->get('AudioOut').' is not a supported AudioCodec for AudioOut.') if $block->get('AudioOut') !~ /(flac)/i;
		}
		else
		{
            push(@{$errormsg}, 'Invalid Transcode \''.$transcode_block->[1].'\': Invalid MediaType.');
		}

		my %transcode = ();
		$transcode{'Name'} = $transcode_block->[1];
		$transcode{'MediaType'} = $block->get('MediaType');
		$transcode{'AudioIn'} = $audio_codecs{lc($block->get('AudioIn'))} if defined($block->get('AudioIn'));
		$transcode{'AudioOut'} = $audio_codecs{lc($block->get('AudioOut'))} if defined($block->get('AudioOut'));

		push(@{$CONFIG{'TRANSCODING_PROFILES'}}, \%transcode);
	}

	return 1 if (scalar(@{$errormsg}) == 0);
	return 0;
}

1;
