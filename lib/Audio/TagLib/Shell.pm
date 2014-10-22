package Audio::TagLib::Shell;

use 5.008003;
use strict;
use warnings;
use Carp q(croak);
use Cwd q(chdir);

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our @EXPORT_OK = qw(shell);

our @EXPORT    = qw(shell);

our $VERSION   = '1.41';

# support encodings
our @ENCODING  = qw(Latin1 UTF8);

# pre-declared subs
my @callback = qw(open save close title artist album comment genre
                  year track setTitle setArtist setAlbum setComment
                  setGenre setYear setTrack length bitrate sampleRate
                  channels cd exit pwd ls);
use subs map { "_".$_ } @callback;
use subs qw(shell __complete);

# global default command callback map
#{
#    no strict 'refs';
    our %CMD   = map { +"$_" => \&{"_".$_}, } @callback;
#}
# nice alias
$CMD{quit} = $CMD{exit};
$CMD{bye}  = $CMD{exit};

# private reference to current openned file
# to make sure there is ONLY ONE file openned
my $fileref  = undef;
# PS1 similar to normal shell
# change to q(tag:o>) after a successful open action
my $ps1      = q(tag:>);
# encoding got from locale settings
my $encoding = undef;

# Preloaded methods go here.

# try to complete command line for user
# similar to <TAB> in bash
# no need to escape space while input
sub __complete(@) {
    # @_ is (current last param, entire command line, length)
    my ($last, $cmd) = @_;
    local *DIR;
    if($last eq $cmd) {
        # action only
        # complete list is `keys %CMD' if no input
        return sort keys %CMD if $cmd eq '';
        # complete list grepped from `keys $CMD' 
        return sort grep { m/^\Q$last\E/ } keys %CMD;
    } else {
        # action + path
        my ($action, $path) = split / /, $cmd, 2;
        my (@entry, @match);
        #print "\npath = '$path'\n";
        if($path) {
            # return if end with a space
            return +() if (substr($path, -1, 1) eq ' ');
            # glob all the matched entries if possible
            
            if($path =~ m#^((?:/?[^/]*)*)/(.*)#o) {
                #print "\n1 = '$1'\n2 = '$2'";
                # $1 is basedir or null
                return +() unless -d "$1/";
                    
                opendir DIR, "$1/" or do {
                    #warn "opendir: $!";
                    return +();
                };
                @entry = readdir DIR;
                closedir DIR or warn "closedir: $!";
                if($2) {
                    @match = sort grep { m/^\Q$2\E/ } @entry;
                    if(scalar(@match) == 1) {
                        # complete will add a ' ' automatically
                        # for a file ok
                        # for a dir this will block the
                        # following match
                        # a small trick here to remove the
                        # tail space for dir
                        my $file = "$1/".$match[0];
                        #print $1, "\n";
                        
                        my $complete;
                        # check space in $2 and then $1
                        # $1 will be replaced after next reg-match
                        my $dir = $1;
                        my $name = $2;
                        if ($name and $name =~ m/ /o) {
                            $complete = substr($match[0], 
                                               rindex($name, " ")+1);
                        } elsif ($dir and $dir =~ m/ /o) {
                            $complete = (split / /, $dir)[-1]."/".$match[0];
                        } else {
                            $complete = $file;
                        }
                        if (-d $file) {
                            return +($complete."/", 
                                     $complete."/ ");
                        } else {
                            return $complete;
                        }
                    } elsif (scalar(@match) == 0) {
                        # no match, no complete
                        return +();
                    } else {
                        # grep the match list and try to get the
                        # longest common string
                        my ($min_match) = (sort { 
                            length($a) <=> length($b) } @match)[0];
                        my $min_length = length($min_match);
                        my $common;
                        
                        COMMON: for (my $length =
                                       length($2);;$length++) {
                            
                            if($length == $min_length) {
                                $common = $min_match;
                                last COMMON;
                            }
                            
                            my $char = substr($match[0], $length, 1);
                            #print "\nchar = $char\n";
                            foreach (@match[1 .. $#match]) {
                                if(substr($_, $length, 1) ne $char) {
                                    $common = substr($match[0], 0,
                                                     $length);
                                    last COMMON;
                                }    
                            }
                        }
                        
                        if ($2 eq $common) {
                            # $2 is the longest common string
                            return +(@match, undef);
                        } else {
                            # check space in $2 and then $1
                            my $complete;
                            my $dir = $1;
                            my $name = $2;
                            #print $name, "\n";
                            if ($name and $name =~ m/ /o) {
                                $complete = substr($common, 
                                                  rindex($name, " ")+1);
                            } elsif ($dir and $dir =~ m/ /o) {
                                $complete = (split / /, $dir)[-1].
                                  "/$common";
                            } else {
                                $complete = "$1/$common";
                            }
                            return +("$complete", 
                                     "$complete ");
                        }
                        # NOREACH
                    }
                } else {
                    return sort @entry;
                }
            } else {
                # search under cwd
                opendir DIR, "." or do {
                    #warn "opendir: $!";
                    return +();
                };
                @entry = readdir DIR;
                closedir DIR or warn "closedir: $!";
                @match = sort grep { m/^\Q$path\E/ } @entry;
                if(scalar(@match) == 1) {
                    my $file = $match[0];
                    my $complete;
                    # check space in $path
                    # $1 will be replaced after next reg-match
                    my $name = $path;
                    if ($name and $name =~ m/ /o) {
                        $complete = (split / /, $name)[-1]."/".$match[0];
                    } else {
                        $complete = $file;
                    }
                    if (-d $file) {
                        return +($complete."/", 
                                 $complete."/ ");
                    } else {
                        return $complete;
                    }
                } elsif (scalar(@match) == 0) {
                    return +();
                } else {
                    # grep the match list and try to get the
                    # longest common string
                    my ($min_match) = (sort { 
                        length($a) <=> length($b) } @match)[0];
                    my $min_length = length($min_match);
                    my $common;
                    
                    COMMON: for (my $length =
                                   length($path);;$length++) {

                        if($length == $min_length) {
                            $common = $min_match;
                            last COMMON;
                        }
                        
                        my $char = substr($match[0], $length, 1);
                        foreach (@match[1 .. $#match]) {
                            if(substr($_, $length, 1) ne $char) {
                                $common = substr($match[0], 0,
                                                 $length);
                                last COMMON;
                            }    
                        }
                    }
                    
                    if ($path eq $common) {
                        # $path is the longest common string
                        return +(@match, undef);
                    } else {
                        # check space in $path
                        my $complete;
                        my $name = $path;
                        if ($name and $name =~ m/ /o) {
                            $complete = substr($common, 
                                               rindex($name, " ")+1);
                        } else {
                            $complete = "$path/$common";
                        }
                        return +("$complete", 
                                 "$complete ");
                    }
                    # NOREACH
                }
            }
        } else {
            # no param
            # ls all entries under cwd
            opendir DIR, "." or do { 
                #warn "opendir: $!";
                return +();
            };
            @entry = readdir DIR;
            closedir DIR or warn "closedir: $!";
            return sort grep { /^[^.]/o } @entry;
        }
    }
    # NOREACH
}

# main sub exported
# start the shell
sub shell() {
    # check locale first
    # follow the normal sequence LC_CTYPE -> LC_ALL -> LANG
    my $lc;
    if (exists $ENV{LC_CTYPE}) {
        $lc = $ENV{LC_CTYPE};
    } elsif (exists $ENV{LC_ALL}) {
        $lc = $ENV{LC_ALL};
    } elsif (exists $ENV{LANG}) {
        $lc = $ENV{LANG};
    }
    if(defined $lc and $lc =~
         m/^([a-z]{2}_[A-Z]{2})
           (?:\.(?i:([a-z_\-_0-9]+)))?
           (?:@(?i:[a-z_0-9]+))?$/xo) {
        if(defined $2 and lc($2) eq 'utf8' or lc($2) eq 'utf-8') {
            $encoding = 1;
            binmode STDOUT, ":utf8";
        } elsif(not defined $2 and $1 eq 'en_US') {
            $encoding = 0;
        } else {
            croak(sprintf("currently only support %s\n", 
                          join(" ", @ENCODING)));
        }
    } else {
        croak("no valid locale setting found");
    }
    
    # open shell
    require Term::ReadLine;
    my $term = Term::ReadLine->new("TagLib mini shell");
    my $attr = $term->Attribs;
    if($term->ReadLine eq "Term::ReadLine::Gnu") {
        $attr->{attempted_completion_function} =
          __PACKAGE__."::__complete";
    } else {
        $attr->{completion_function} = __PACKAGE__. "::__complete";
    }
    my $line;
    my $OUT = $term->OUT || \*STDOUT;
    select $OUT;
    $| = 1;
    LOOP: while (1) {
        $line = $term->readline($ps1);
        chomp $line;
        next LOOP unless $line;
        $line =~ s/\s+$//o;
        #print "'$line'\n";
        my ($cmd, $file) = split / /, $line, 2;
        foreach (keys %CMD) {
            # exact match here
            if ($cmd eq $_) {
                no strict 'refs';
                print &{$CMD{$cmd}}($file);
                next LOOP;
            }
        }
        # no match command found
        print "no such command!\n";
        next LOOP;
    }
}

# evaluate the file permission for specific action
# read or write
sub __permission {
    my $file = $_[0];
    my $perm =  $_[1] ? 02 : 04;
    my ($mode, $uid, $gid) = (stat $file)[2, 4, 5];
    if($uid == $<) {
        # the same user
        return 0 
          unless(($mode & 00700) >> 6 & $perm);
    } elsif($gid == $() {
        # the same group
        return 0 
          unless(($mode & 00070) >> 3 & $perm);
    } else {
        # the other
        return 0 
          unless(($mode & 00007) & $perm);
    }
    return 1;
}

sub _open {
    if (defined $fileref) {
        return << "EOM" ;
There is file openned, close or save first.
EOM
    } else {
        # check before open
        my $file = shift or return "no file specified\n";
        return "not found\n" unless -e $file;
        return "no read permission\n" unless __permission($file);
        warn "no write permission\n" unless __permission($file, 1);
        # open file
        require Audio::TagLib::FileRef;
        $fileref = Audio::TagLib::FileRef->new($file);
        $ps1 = "tag:o>";
        return "file openned successfully\n";
    }
}

sub _save {
    if(defined $fileref) {
        if($fileref->save()) {
            undef $fileref;
            $ps1 = "tag:>";
            return "file saved successfully\n";
        } else {
            return "file could not be saved\n";
        }
    } else {
        return "no file openned\n";
    }
}

sub _close {
    undef $fileref if(defined $fileref);
    $ps1 = "tag:>";
}

sub _title {
    if(defined $fileref) {
        return $fileref->tag()->title()->toCString(
            $ENCODING[$encoding] eq 'UTF8' ? 1 : 0). "\n";
    } else {
        return "no file openned\n";
    }
}

sub _artist {
    if(defined $fileref) {
        return $fileref->tag()->artist()->toCString(
            $ENCODING[$encoding] eq 'UTF8' ? 1 : 0). "\n";
    } else { 
        return "no file openned\n";
    }
}

sub _album {
    if(defined $fileref) {
        return $fileref->tag()->album()->toCString(
            $ENCODING[$encoding] eq 'UTF8' ? 1 : 0). "\n";
    } else {
        return "no file openned\n";
    }
}

sub _comment {
    if(defined $fileref) {
        return $fileref->tag()->comment()->toCString(
            $ENCODING[$encoding] eq 'UTF8' ? 1 : 0). "\n";
    } else {
        return "no file openned\n";
    }
}

sub _genre {
    if(defined $fileref) {
        return $fileref->tag()->genre()->toCString(
            $ENCODING[$encoding] eq 'UTF8' ? 1 : 0). "\n";
    } else {
        return "no file openned\n";
    }
}

sub _year {
    if(defined $fileref) {
        return $fileref->tag()->year(). "\n";
    } else {
        return "no file openned\n";
    }
}

sub _track {
    if(defined $fileref) {
        return $fileref->tag()->track(). "\n";
    } else {
        return "no file openned\n";
    }
}

sub _setTitle {
    my $title = $_[0] ? 
      Audio::TagLib::String->new($_[0], $ENCODING[$encoding]) : 
        Audio::TagLib::String->null();
    if(defined $fileref) {
        $fileref->tag()->setTitle($title);
        return "title set\n";
    } else {
        return "no file openned\n";
    }
}

sub _setArtist {
    my $artist = $_[0] ? 
      Audio::TagLib::String->new($_[0], $ENCODING[$encoding]) : 
        Audio::TagLib::String->null();
    if(defined $fileref) {
        $fileref->tag()->setArtist($artist);
        return "artist set\n";
    } else {
        return "no file openned\n";
    }
}

sub _setAlbum {
    my $album = $_[0] ? 
      Audio::TagLib::String->new($_[0], $ENCODING[$encoding]) : 
        Audio::TagLib::String->null();
    if(defined $fileref) {
        $fileref->tag()->setAlbum($album);
        return "album set\n";
    } else {
        return "no file openned\n";
    }
}

sub _setComment {
    my $comment = $_[0] ? 
      Audio::TagLib::String->new($_[0], $ENCODING[$encoding]) : 
        Audio::TagLib::String->null();
    if(defined $fileref) {
        $fileref->tag()->setComment($comment);
        return "comment set\n";
    } else {
        return "no file openned\n";
    }
}

sub _setGenre {
    my $genre = $_[0] ? 
      Audio::TagLib::String->new($_[0], $ENCODING[$encoding]) : 
        Audio::TagLib::String->null();
    if(defined $fileref) {
        $fileref->tag()->setGenre($genre);
        return "genre set\n";
    } else {
        return "no file openned\n";
    }
}

sub _setYear {
    my $year = shift or return "no year to set\n";
    if(defined $fileref) {
        $fileref->tag()->setYear($year);
        return "year set\n";
    } else {
        return "no file openned\n";
    }
}

sub _setTrack {
    my $track = shift or return "no track to set\n";
    if(defined $fileref) {
        $fileref->tag()->setTrack($track);
        return "track set\n";
    } else {
        return "no file openned\n";
    }
}

sub _length {
    if(defined $fileref) {
        return $fileref->audioProperties()->length(). "\n";
    } else {
        return "no file openned\n";
    }
}

sub _bitrate {
    if(defined $fileref) {
        return $fileref->audioProperties()->bitrate(). "\n";
    } else {
        return "no file openned\n";
    }
}

sub _sampleRate {
    if(defined $fileref) {
        return $fileref->audioProperties()->sampleRate(). "\n";
    } else {
        return "no file openned\n";
    }
}

sub _channels {
    if(defined $fileref) {
        return $fileref->audioProperties()->channels(). "\n";
    } else {
        return "no file openned\n";
    }
}

sub _cd {
    my $dir = shift || $ENV{HOME};
    #print $dir. "\n";
    return "not a directory\n" unless -d $dir;
    chdir $dir or return "cd: $!\n";
}

sub _exit {
    if(defined $fileref) {
        return "there's file openned, save or close first\n";
    } else {
        exit(0);
    }
}

sub _pwd {
    return $ENV{PWD}. "\n";
}

# simply list all the entries in cwd
sub _ls {
    local (*CWD);
    opendir CWD, "." or return "can't open cwd\n";
    my @entry = sort grep { m/^[^.]/ } readdir CWD;
    closedir CWD or warn "closedir: $!\n";
    return join("\t"x2, @entry), "\n";
}

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Audio::TagLib::Shell - A mini shell of Audio::TagLib

=head1 SYNOPSIS

  $> perl -MAudio::TagLib::Shell -e shell
  $tag:>open <file>
  file openned successfully
  $tag:o>title
  <title in tag>
  $tag:o>artist
  <artist in tag>
  $tag:o>channels
  2
  $tag:o>setComment blah blah blah
  comment set successfully
  $tag:o>comment
  blah blah blah
  $tag:o>save
  data saved successfully
  $tag:>exit

=head1 DESCRIPTION

A mini shell of L<Audio::TagLib|Audio::TagLib>, for viewing and
editing common audio meta data on the fly. 

The functionality offerred follows the abstract interface designing of 
L<Audio::TagLib|Audio::TagLib>, for instance,
L<Audio::TagLib::Tag|Audio::TagLib::Tag> and
L<Audio::TagLib::AudioProperties|Audio::TagLib::AudioProperties>. 

=head2 WHAT CAN DO

Simply start the shell and push E<lt>TABE<gt>. All available commands
will appear. 

=head2 HOW TO GET & SET DATA

First of all, choose an audio file and open it. Then play your game.

B<Don't> forget to use E<lt>TABE<gt> ;-) 

No need to escape the space in path.

=head2 A SMALL RULE

Every game should have rule. Pls save or close current openned file
before openning another one. C<close> will discard all changes you
made while C<save> does what it should do.

B<hmmm..> I<$tag:>> vs. I<$tag:o>> 

=head2 MORE WORDS ABOUT set???

No need to use I<" "> to comment your data. Just C<setComment your
comment> directly. C<setComment> will clear current comment.

=head2 EXPORT

C<shell> by default.

=head1 SEE ALSO

L<Audio::TagLib> L<Audio::TagLib::Tag|Audio::TagLib::Tag>
L<Audio::TagLib::AudioProperties|Audio::TagLib::AudioProperties> 

=head1 AUTHOR

Dongxu Ma, E<lt>dongxu.ma@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Dongxu Ma

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.


=cut
