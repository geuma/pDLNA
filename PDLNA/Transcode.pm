package PDLNA::Transcode;
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

use PDLNA::Config;
use PDLNA::Media;

sub shall_we_transcode
{
	my $media_data = shift;
	my $client_data = shift;

	if ($CONFIG{'LOW_RESOURCE_MODE'} == 1 || $$media_data{'external'} != 0 || !defined($$media_data{'container'}))
	{
		return 0;
	}

	foreach my $profile (@{$CONFIG{'TRANSCODING_PROFILES'}})
	{
		next if $$media_data{'container'} ne $profile->{'ContainerIn'};

		if ($$media_data{'media_type'} eq 'video')
		{
			next if $$media_data{'video_codec'} ne $profile->{'VideoIn'};
		}

		next if $$media_data{'audio_codec'} ne $profile->{'AudioIn'};

		my $matched_ip = 0;
        foreach my $ip (@{$$profile{'ClientIPs'}})
		{
			$matched_ip++ if $ip->match($$client_data{'ip'});
		}
		next if $matched_ip == 0;

		$$media_data{'command'} = get_transcode_command($media_data, $profile->{'ContainerOut'}, $profile->{'VideoOut'}, $profile->{'AudioOut'});
		$$media_data{'container'} = $profile->{'ContainerOut'};
		$$media_data{'audio_codec'} = $profile->{'AudioOut'};
		$$media_data{'video_codec'} = $profile->{'VideoOut'};
		$$media_data{'file_extension'} = PDLNA::Media::details($profile->{'ContainerOut'}, undef, $profile->{'AudioOut'}, 'FileExtension');
		$$media_data{'mime_type'} = PDLNA::Media::details($profile->{'ContainerOut'}, undef, $profile->{'AudioOut'}, 'MimeType');
		return 1;
	}
	return 0;
}

sub get_transcode_command
{
	my $media_data = shift;
	my $container = shift;
	my $video_codec = shift || '';
	my $audio_codec = shift;

	my $command = $CONFIG{'FFMPEG_BIN'}.' -i "'.$$media_data{'fullname'}.'" ';
	$command .= PDLNA::Media::details($container, $video_codec, $audio_codec, 'FFmpegParam').' pipe: 2>/dev/null';

	return $command;
}

1;
