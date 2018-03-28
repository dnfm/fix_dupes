#!/usr/bin/perl

=head1 fix_dupes

A simple script I wrote that walks through a hierarchy of directories, and
looks for duplicate files.  If it finds any, it will hard link them to each
other.

This was a result of me trying to organise my 'media' folders.  I had movies,
mp3s, and tvshows that I'd ripped from disc and then copied around into
hierarchies, but then realised that I had copies in different locations of the
same file for different media serving devices.  This was a waste of space.

It will simply go through a hierarchy, and md5sum each file.  If their md5sum
matches, and they aren't already pointing at the same inode, it will rm one of
the copies, and then cp -l them.

It does most of its work via shell, and is pretty rudimentary, but it saved me
a bunch of space.

=head1 NO WARRANTY

Please keep in mind, this is a simple one-off -- if you want to be sure it's
going to do the right thing, then comment out the unlink and cp -l below, and
run it so it just outputs what it WOULD do.

Even then, it could blow away data if it screws up.  Keep that in mind.

Also keep in mind there's the possibility for md5 hash collisions, as well as
the fact that if a file is > 100M in size, it will only md5sum the first and
last MB of the file.  This is just for time savings.  You could comment that
out too if you so desired.

If I find more than just me is using this, I might update it to support
--dry-run or to only output shell commands you can peruse and run yourself or
something.

But either way: use this program at your own risk.  Please don't get mad at me
if it eats your data or sets your cat on fire.

=cut

use strict;
use warnings;

die "Usage: $0 <dir>\n" if !$ARGV[0];
my $t_saved = parse_dir( $ARGV[0] );

warn "Saved " . h_bytes( $t_saved ) if $t_saved;

my %files_by_hash;

my $parsed = 0;

sub parse_dir {
	my ( $dir, $saved ) = @_;
	
    $saved //= 0;

	opendir my( $dh ), $dir;
	
	while ( my $dir_entry = readdir $dh ) {
		next if $dir_entry =~ m{^[.]};
		
        foreach my $entry ( <"$dir/$dir_entry/*"> ) {
            if ( -d $entry ) {
                parse_dir( $entry, $saved );

                next;
            }

            warn "Parsed $parsed files.\n" if !( ++$parsed % 100 );

            my $md5;
            my $size = -s $entry;

            my $escaped = escape( $entry );

            if ( $size > 100_000_000 ) {
                ( $md5 ) = split m{\s+}, `( head -c 1M $escaped ; tail -c 1M $escaped ) | md5sum`;
            }
            else {
                ( $md5 ) = split m{\s+}, `md5sum $escaped`;
            }

            my ( $i ) = split m{\s+}, `ls -i $escaped`;

            my $hash = {
                size     => $size,
                filename => $entry,
                escaped  => $escaped,
                inode    => $i,
                md5      => $md5,
            };

            next if !$md5 || !$i || !$size;

            if ( $files_by_hash{ $md5 } && $files_by_hash{ $md5 }->{ inode } ne $i ) {
                warn "DUPE:\n\t$files_by_hash{ $md5 }->{ filename }\n\t$entry\n";
                unlink $entry;
                `cp -l $files_by_hash{ $md5 }->{ escaped } $escaped`;
                $saved += $size;
            }
            else {
                $files_by_hash{ $md5 } = $hash;
            }
        }
	}

    return $saved;
}

sub h_bytes {
    my ( $size ) = @_;

    my @prefixes = qw( B kB MB GB TB PB );
    my $div_by   = int( log( $size ) / log( 1_024 ) * 1.1 );

       $div_by   = $#prefixes if $div_by > $#prefixes;
    my $prefix   = $prefixes[$div_by];
    my $fmt_size = $size / 1024 ** $div_by;
    my $format   = int( $fmt_size ) == $fmt_size ? '%d' : '%.2f';

    return sprintf( "$format%s", $fmt_size, $prefix );
}

# Filthy, but whatever.  This is a one-off.
sub escape {
    my ( $p ) = @_;

    $p =~ s/'/'"'"'/g;

    return "'$p'";
}
