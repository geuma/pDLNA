package PDLNA::Statistics;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2015 Stefan Heumader <stefan@heumader.at>
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

use Proc::ProcessTable;

use PDLNA::Config;
use PDLNA::Daemon;
use PDLNA::Database;
use PDLNA::Log;

sub get_proc_information
{
	my %statistics = (
		'ppid' => 0,
		'start' => 0,
		'priority' => 0,
		'pctcpu' => 0,
		'vmsize' => 0,
		'rssize' => 0,
		'pctmem' => 0,
	);

	my $proc = Proc::ProcessTable->new();
	my %fields = map { $_ => 1 } $proc->fields;
	return undef unless exists $fields{'pid'};
	my $pid = PDLNA::Daemon::read_pidfile($CONFIG{'PIDFILE'});
	foreach my $process (@{$proc->table()})
	{
		if ($process->pid() eq $pid)
		{
			$statistics{'ppid'} = $process->{ppid} if defined($process->{ppid});
			$statistics{'start'} = $process->{start} if defined($process->{start});
			$statistics{'priority'} = $process->{priority} if defined($process->{priority});
			$statistics{'pctcpu'} = $process->{pctcpu} if defined($process->{pctcpu});
			$statistics{'vmsize'} = $process->{size} if defined($process->{size});
			$statistics{'vmsize'} = $process->{vmsize} if defined($process->{vmsize});
			$statistics{'rssize'} = $process->{rss} if defined($process->{rss});
			$statistics{'rssize'} = $process->{rssize} if defined($process->{rssize});
			$statistics{'pctmem'} = $process->{pctmem} if defined($process->{pctmem});

			last;
		}
	}

	return %statistics;
}

sub write_statistics_periodic
{
	PDLNA::Log::log('Starting thread for writing statistics periodically.', 1, 'default');
	while(1)
	{
		my $dbh = PDLNA::Database::connect();
		$dbh->{AutoCommit} = 0;

		#
		# MEMORY
		#
		my %proc_info = get_proc_information();
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO stat_mem (date, vms, rss) VALUES (?,?,?)',
				'parameters' => [ time(), $proc_info{'vmsize'}, $proc_info{'rssize'}, ],
			},
		);

		#
		# MEDIA ITEMS
		#
		my ($audio_amount, $audio_size) = PDLNA::ContentLibrary::get_amount_size_items_by($dbh, 'media_type', 'audio');
		my ($image_amount, $image_size) = PDLNA::ContentLibrary::get_amount_size_items_by($dbh, 'media_type', 'image');
		my ($video_amount, $video_size) = PDLNA::ContentLibrary::get_amount_size_items_by($dbh, 'media_type', 'video');
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO stat_items (date, audio, audio_size, image, image_size, video, video_size) VALUES (?,?,?,?,?,?,?)',
				'parameters' => [ time(), $audio_amount, $audio_size, $image_amount, $image_size, $video_amount, $video_size, ],
			},
		);

		$dbh->commit();
		PDLNA::Database::disconnect($dbh);

		sleep 60;
	}
}

1;
