use warnings;
use strict;
use Cwd;
use  File::Basename;

sub go_mod_path () {
    my $dir = getcwd;
    while (1) {
        my $go_mod_path = "$dir/go.mod";
        if (-e $go_mod_path) {
            print "FOUND: $go_mod_path";
            return $go_mod_path;
        }
        last if $dir eq '/';
        $dir = dirname($dir);
    }
    die "go.mod not found"
}

sub list_modules () {
    my $go_mod = go_mod_path();
    open(my $f, $go_mod) || die "$go_mod: $!";
    while (my $row = <$f>) {
        chomp $row;
        print "$row\n";
    }
}

print(list_modules())
