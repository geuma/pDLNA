package PDLNA::FFmpeg;

=head1 NAME

PDLNA::FFmpeg - support transcoding.

=head1 DESCRIPTION

works out formats and media information.

=cut

use strict;
use warnings;

=head1 LIBRARY FUNCTIONS

=over 12

=item internal libraries

=begin html

</p>
<a href="./Config.html">PDLNA::Config</a>,
<a href="./Media.html">PDLNA::Media</a>,
<a href="./Log.html">PDLNA::Log</a>,
</p>

=end html

=item external libraries

None.

=back

=cut

use PDLNA::Config;
use PDLNA::Media;
use PDLNA::Log;

# this represents the beatuiful codec names and their internal (in the db) possible values (from FFmpeg)
my %AUDIO_CODECS = (
	'aac' => [ 'mpeg4aac', 'aac', ],
	'ac3' => [ 'ac3', ],
	'flac' => [ 'flac', ],
	'mp3' => [ 'mp3', ],
	'vorbis' => [ 'vorbis', ],
	'wav' => [ 'pcm_s16le', ],
	'wmav1' => [ 'wmav1', ],
	'wmav2' => [ 'wmav2', ],
);

# this represents the beatuiful codec names and their internal (in the db) possible container names (from FFmpeg)
my %AUDIO_CONTAINERS = (
	'aac' => 'mov',
	'ac3' => 'ac3',
	'flac' => 'flac',
	'mp3' => 'mp3',
	'vorbis' => 'ogg',
	'wav' => 'wav',
	'wmav1' => 'asf',
	'wmav2' => 'asf',
);

# this represents the beatuiful codec names and their FFmpeg decoder formats
my %FFMPEG_DECODE_FORMATS = (
	'aac' => 'aac',
	'ac3' => 'ac3',
	'flac' => 'flac',
	'mp3' => 'mp3',
	'vorbis' => 'ogg',
	'wav' => 'wav',
	'wmav1' => 'asf',
	'wmav2' => 'asf',
);

# this represents the beatuiful codec names and their FFmpeg encoder formats
my %FFMPEG_ENCODE_FORMATS = (
	'aac' => 'm4v',
	'ac3' => 'ac3',
	'flac' => 'flac',
	'mp3' => 'mp3',
	'vorbis' => 'ogg',
	'wav' => 'wav',
	'wmav1' => 'asf',
	'wmav2' => 'asf',
);

# this represents the beautiful codec names and their FFmpeg decode codecs
my %FFMPEG_AUDIO_DECODE_CODECS = (
	'aac' => 'aac',
	'ac3' => 'ac3',
	'flac' => 'flac',
	'mp3' => 'mp3',
	'vorbis' => 'vorbis',
	'wav' => 'pcm_s16le',
	'wmav1' => 'wmav1',
	'wmav2' => 'wmav2',
);

# this represents the beautiful codec names and their FFmpeg encode codecs
my %FFMPEG_AUDIO_ENCODE_CODECS = (
	'aac' => 'libfaac',
	'ac3' => 'ac3',
	'flac' => 'flac',
	'mp3' => 'libmp3lame',
	'vorbis' => 'libvorbis',
	'wav' => 'pcm_s16le',
	'wmav1' => 'wmav1',
	'wmav2' => 'wmav2',
);

# additional parameters for FFmpeg
my %FFMPEG_AUDIO_ENCODE_PARAMS = (
	'aac' => [],
	'ac3' => [],
	'flac' => [],
	'mp3' => [],
	'vorbis' => [],
	'wav' => [],
	'wmav1' => [ '-ab 32k', ],
	'wmav2' => [ '-ab 32k', ],
);

=head1 METHODS

=over

=item is_supported_audio_decode_codec()

=cut

sub is_supported_audio_decode_codec
{
	my $codec = shift;

	return $FFMPEG_AUDIO_DECODE_CODECS{$codec} if defined($FFMPEG_AUDIO_DECODE_CODECS{$codec});
	return undef;
}


=item is_supported_audio_encode_codec()

=cut

sub is_supported_audio_encode_codec
{
	my $codec = shift;

	return $FFMPEG_AUDIO_ENCODE_CODECS{$codec} if defined($FFMPEG_AUDIO_ENCODE_CODECS{$codec});
	return undef;
}


=item is_supported_decode_format()

=cut

sub is_supported_decode_format
{
	my $format = shift;

	return $FFMPEG_DECODE_FORMATS{$format} if defined($FFMPEG_DECODE_FORMATS{$format});
	return undef;
}


=item is_supported_encode_format()

=cut

sub is_supported_encode_format
{
	my $format = shift;

	return $FFMPEG_ENCODE_FORMATS{$format} if defined($FFMPEG_ENCODE_FORMATS{$format});
	return undef;
}

=item get_beautiful_audio_decode_codec()

=cut

sub get_beautiful_audio_decode_codec
{
	my $codec = shift;

	foreach my $beautiful (keys %FFMPEG_AUDIO_DECODE_CODECS)
	{
		return $beautiful if $FFMPEG_AUDIO_DECODE_CODECS{$beautiful} eq $codec;
	}

	return undef;
}


=item get_beautiful_audio_encode_codec()

=cut

sub get_beautiful_audio_encode_codec
{
	my $codec = shift;

	foreach my $beautiful (keys %FFMPEG_AUDIO_ENCODE_CODECS)
	{
		return $beautiful if $FFMPEG_AUDIO_ENCODE_CODECS{$beautiful} eq $codec;
	}

	return undef;
}


=item get_beautiful_decode_format()

=cut

sub get_beautiful_decode_format
{
	my $format = shift;

	foreach my $beautiful (keys %FFMPEG_DECODE_FORMATS)
	{
		return $beautiful if $FFMPEG_DECODE_FORMATS{$beautiful} eq $format;
	}

	return undef;
}


=item get_beautiful_encode_format()

=cut

sub get_beautiful_encode_format
{
	my $format = shift;

	foreach my $beautiful (keys %FFMPEG_ENCODE_FORMATS)
	{
		return $beautiful if $FFMPEG_ENCODE_FORMATS{$beautiful} eq $format;
	}

	return undef;
}

=item get_decode_format_by_audio_codec()

=cut

sub get_decode_format_by_audio_codec
{
	my $codec = shift;

	return $FFMPEG_DECODE_FORMATS{$codec} if defined($FFMPEG_DECODE_FORMATS{$codec});
	return undef;
}


=item get_encode_format_by_audio_codec()

=cut

sub get_encode_format_by_audio_codec
{
	my $codec = shift;

	return $FFMPEG_ENCODE_FORMATS{$codec} if defined($FFMPEG_ENCODE_FORMATS{$codec});
	return undef;
}

=item shall_we_transcode()

=cut

sub shall_we_transcode
{
	my $media_data = shift;
	my $client_data = shift;

	if ($CONFIG{'LOW_RESOURCE_MODE'} == 1 || $$media_data{'external'} != 0 || !defined($$media_data{'container'}))
	{
		return 0;
	}

	PDLNA::Log::log('Looking for a matching Transcoding Profile for Container: '.$$media_data{'container'}.', AudioCodec: '.$$media_data{'audio_codec'}.'.', 2, 'transcoding');

	foreach my $profile (@{$CONFIG{'TRANSCODING_PROFILES'}})
	{
		next if $$media_data{'media_type'} ne $profile->{'MediaType'};

		my $matched_profile = 0;
		if ($$media_data{'media_type'} eq 'audio')
		{
			if (grep(/^$$media_data{'audio_codec'}$/, @{$AUDIO_CODECS{$profile->{'AudioCodecIn'}}}))
			{
				$matched_profile = 1;
			}
		}
		elsif ($$media_data{'media_type'} eq 'video')
		{
			next;
		}
		else
		{
			next;
		}
		next if $matched_profile == 0;

		my $matched_ip = 0;
		foreach my $ip (@{$$profile{'ClientIPs'}})
		{
			$matched_ip++ if $ip->match($$client_data{'ip'});
		}
		next if $matched_ip == 0;

		if ($$media_data{'media_type'} eq 'audio')
		{
			PDLNA::Log::log('Found a matching Transcoding Profile with Name: '.$profile->{'Name'}.'.', 2, 'transcoding');

			$$media_data{'audio_codec'} = $AUDIO_CODECS{$profile->{'AudioCodecOut'}}->[0];
			$$media_data{'container'} = $AUDIO_CONTAINERS{$profile->{'AudioCodecOut'}};
			$$media_data{'file_extension'} = PDLNA::Media::details($$media_data{'container'}, undef, $$media_data{'audio_codec'}, 'FileExtension');
			$$media_data{'mime_type'} = PDLNA::Media::details($$media_data{'container'}, undef, $$media_data{'audio_codec'}, 'MimeType');
			PDLNA::Log::log("$$media_data{'container'}, $$media_data{'audio_codec'}, $$media_data{'file_extension'}, $$media_data{'mime_type'}", 3, 'transcoding');

			$$media_data{'command'} = get_transcode_command($media_data, $profile->{'AudioCodecOut'});

			return 1;
		}
		elsif ($$media_data{'media_type'} eq 'video')
		{
		}
	}
	return 0;
}


=item get_ffmpeg_stream_command()

=cut

sub get_ffmpeg_stream_command
{
	my $media_data = shift;

	my $command = $CONFIG{'FFMPEG_BIN'}.' -i "'.$$media_data{'fullname'}.'"';
	$command .= ' -vcodec copy' if $$media_data{'media_type'} eq 'video';
	$command .= ' -acodec copy';
	$command .= ' -f '.$$media_data{'container'};
	$command .= ' pipe:';
	$command .= ' 2>/dev/null';

	return $command;
}


=item get_transcode_command()

=cut

sub get_transcode_command
{
	my $media_data = shift;
	my $audio_codec = shift;

	my $command = $CONFIG{'FFMPEG_BIN'}.' -i "'.$$media_data{'fullname'}.'"';
	$command .= ' -acodec '.$FFMPEG_AUDIO_ENCODE_CODECS{$audio_codec}.' ';
	if (scalar @{$FFMPEG_AUDIO_ENCODE_PARAMS{$audio_codec}} > 0)
	{
		$command .= join(' ', @{$FFMPEG_AUDIO_ENCODE_PARAMS{$audio_codec}});
	}
	$command .= ' -f '.$FFMPEG_ENCODE_FORMATS{$audio_codec};
	$command .= ' pipe: 2>/dev/null';

	PDLNA::Log::log('Command for Transcoding Profile: '.$command.'.', 3, 'transcoding');

	return $command;
}


=item get_ffmpeg_command()

=cut

sub get_ffmpeg_command
{
	my $media_data = shift;

	my $command = $CONFIG{'FFMPEG_BIN'}.' -i "'.$$media_data{'fullname'}.'"';
	$command .= ' -acodec copy';
	$command .= ' -f '.$AUDIO_CONTAINERS{$$media_data{'audio_codec'}};
	$command .= ' pipe: 2>/dev/null';

	PDLNA::Log::log('Command for streaming: '.$command.'.', 3, 'transcoding');

	return $command;
}

=item get_ffmpeg_formats()

parse FFmpeg capabilities

=cut

sub get_ffmpeg_formats
{
	my $ffmpeg_bin = shift;
	my $decode = shift;
	my $encode = shift;

	open(CMD, $CONFIG{'FFMPEG_BIN'}.' -formats 2>&1 |');
	my @output = <CMD>;
	close(CMD);

	unless ($output[0] =~ /^ffmpeg\s+version\s+(.+),\scopyright/i)
	{
		return 0;
	}

	foreach my $line (@output)
	{
		if ($line =~ /\s+([DE\s]{2})\s([a-z0-9\_]+)\s+/)
		{
			my $support = $1;
			my $codec = $2;

			next if !defined($support);
			next if !defined($codec);

			if (substr($support, 0, 1) eq 'D')
			{
				push(@{$decode}, $codec);
			}
			if (substr($support, 1, 1) eq 'E')
			{
				push(@{$encode}, $codec);
			}
		}
	}

	return 1;
}

=item get_ffmpeg_codecs()

=cut

sub get_ffmpeg_codecs
{
	my $ffmpeg_bin = shift;
	my $ffmpeg_ver = shift;
	my $audio_decode = shift;
	my $audio_encode = shift;
	my $video_decode = shift;
	my $video_encode = shift;

	my $exitcode = system($CONFIG{'FFMPEG_BIN'}.' -codecs > /dev/null 2>&1'); # FIX ME for WINDOWS
	if (defined($exitcode) && $exitcode == 0)
	{
		open(CMD, $CONFIG{'FFMPEG_BIN'}.' -codecs 2>&1 |');
	}
	else
	{
		open(CMD, $CONFIG{'FFMPEG_BIN'}.' -formats 2>&1 |');
	}
	my @output = <CMD>;
	close(CMD);

	if ($output[0] =~ /^ffmpeg\s+version\s+(.+),\scopyright/i)
	{
		$$ffmpeg_ver = $1;
	}
	else
	{
		return 0;
	}

	foreach my $line (@output)
	{
		if ($line =~ /\s+([A-Z\s]{6})\s([a-z0-9\_]+)\s+/)
		{
			my $support = $1;
			my $codec = $2;

			next if !defined($support);
			next if !defined($codec);

			if (substr($support, 2, 1) eq 'A') # audio codecs
			{
				# $codec = PDLNA::Media::audio_codec_by_beautiful_name($codec);
				# next unless defined($codec);

				if (substr($support, 0, 1) eq 'D')
				{
					push(@{$audio_decode}, $codec);
				}
				if (substr($support, 1, 1) eq 'E')
				{
					push(@{$audio_encode}, $codec);
				}
			}
			elsif (substr($support, 2, 1) eq 'V') # video codecs
			{
				# TODO transcoding profiles for videos
			}
		}
	}

	return 1;
}

=item get_media_info()

use FFmpeg to determine media (audio ir video) details (codecs, ...)

=cut

sub get_media_info
{
	my $file = shift;
	my $info = shift;

	$$info{DURATION} = 0;
	$$info{HZ} = 0;
	$$info{BITRATE} = 0;
	$$info{WIDTH} = 0;
	$$info{HEIGHT} = 0;

	open(FFMPEG, $CONFIG{'FFMPEG_BIN'}.' -i "'.$file.'" 2>&1 |') || PDLNA::Log::fatal('Unable to open FFmpeg :'.$!);
	while (<FFMPEG>)
	{
		if ($_ =~ /Duration:\s+(\d\d):(\d\d):(\d\d).(\d+)\,/)
		{
			$$info{DURATION} = 3600*$1+60*$2+$3; # ignore miliseconds
		}
		#elsif ($_ =~ /Stream\s+.+:\s+Audio:\s+([\w\d]+),\s+(\d+)\s+Hz,\s+.+{,\s+(\d+)\s+kb\/s/)
		elsif ($_ =~ /Stream\s+.+:\s+Audio:\s+([\w\d]+),\s+(.*)/)
		{
			$$info{AUDIO_CODEC} = $1;
			my @tmp = split(/,/, $2);
			foreach (@tmp)
			{
				if ($_ =~ /(\d+)\s+Hz/)
				{
					$$info{HZ} = $1;
				}
				elsif ($_ =~ /(\d+)\s+kb\/s/)
				{
					$$info{BITRATE} = $1*1000;
				}
				else
				{
					# TODO
				}
			}
		}
		elsif ($_ =~ /Stream\s+.+:\s+Video:\s+([\w\d]+),\s+(.*)/)
		{
			$$info{VIDEO_CODEC} = $1;
			my @tmp = split(/,/, $2);
			foreach (@tmp)
			{
				if ($_ =~ /(\d+)x(\d+)/)
				{
					$$info{WIDTH} = $1;
					$$info{HEIGHT} = $2;
				}
				else
				{
					# TODO
				}
			}
		}
		elsif ($_ =~ /Input\s+.+,\s+([\w\d,]+),\s+from/)
		{
			$$info{CONTAINER} = (split(',', $1))[0]; # only take the first container (even if it is a comma seperated list)
		}
	}
	close(CMD);

	if (defined($$info{CONTAINER}) && (defined($$info{VIDEO_CODEC}) || defined($$info{AUDIO_CODEC})))
	{
		$$info{MIME_TYPE} = PDLNA::Media::details($$info{CONTAINER}, $$info{VIDEO_CODEC}, $$info{AUDIO_CODEC}, 'MimeType');
		$$info{TYPE} = PDLNA::Media::details($$info{CONTAINER}, $$info{VIDEO_CODEC}, $$info{AUDIO_CODEC}, 'MediaType');
		$$info{FILE_EXTENSION} = PDLNA::Media::details($$info{CONTAINER}, $$info{VIDEO_CODEC}, $$info{AUDIO_CODEC}, 'FileExtension');

		if (defined($$info{MIME_TYPE}) && defined($$info{TYPE}) && defined($$info{FILE_EXTENSION}))
		{
			PDLNA::Log::log('PDLNA::Media::details() returned for '.$file.": $$info{MIME_TYPE}, $$info{TYPE}, $$info{FILE_EXTENSION}", 3, 'library');
		}
		else
		{
			$$info{CONTAINER} = '' unless $$info{CONTAINER};
			$$info{VIDEO_CODEC} = '' unless $$info{VIDEO_CODEC};
			$$info{AUDIO_CODEC} = '' unless $$info{AUDIO_CODEC};
			PDLNA::Log::log('ERROR: PDLNA::Media::details() was unable to determine details for '.$file.': '.join(', ', ($$info{CONTAINER}, $$info{VIDEO_CODEC}, $$info{AUDIO_CODEC})), 0, 'library');
		}
	}
	else
	{
		PDLNA::Log::log('ERROR: FFmpeg was unable to determine codec and/or container information for '.$file, 0, 'library');
	}
	return 1;
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
