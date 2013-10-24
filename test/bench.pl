use 5.10.0;
use Plack::Builder;
use Cache::Memory::Simple;
use Cache::Memcached::Fast;
use HTTP::Request::Common;
use HTTP::Message::PSGI;
use Benchmark qw/cmpthese timethese/;
use Log::StringFormatter;
use Plack::Session::Store::Cache;

my $cache = Cache::Memory::Simple->new;
#my $cache = Cache::Memcached::Fast->new({servers=>[qw/127.0.0.1:11211/]});

my $app = builder {
    enable 'Session::Simple',
        store => $cache;
    sub {
        $_[0]->{'psgix.session'}->{counter} = 1 unless $_[0]->{'psgix.session'}->{counter};
        [200,[],["OK:".$_[0]->{'psgix.session'}->{counter}]]
    }
};

my $env = req_to_psgi(GET "/");
my $res = $app->($env);
if ( $res->[1]->[1] =~ m!=(.+);! ) {
    $env->{HTTP_COOKIE} = "simple_session=$1";
}

# ==

my $app2 = builder {
    enable 'Session',
        store => Plack::Session::Store::Cache->new(cache=>$cache);
    sub {
        $_[0]->{'psgix.session'}->{counter} = 1 unless $_[0]->{'psgix.session'}->{counter};
        [200,[],["OK:".$_[0]->{'psgix.session'}->{counter}]]
    }
};

my $env2 = req_to_psgi(GET "/");
my $res2 = $app2->($env2);
if ( $res2->[1]->[1] =~ m!=(.+);! ) {
    $env2->{HTTP_COOKIE} = "plack_session=$1";
}

# ===

my $app3 = builder {
    enable 'Session::Simple',
        store => $cache,
        keep_empty => 0;
    sub {
        #$_[0]->{'psgix.session'}->{counter} = 1 unless $_[0]->{'psgix.session'}->{counter};
        [200,[],["OK:".$_[0]->{'psgix.session'}->{counter}]]
    }
};

my $env3 = req_to_psgi(GET "/");
my $res3 = $app3->($env3);
if ( $res3->[1]->[1] =~ m!=(.+);! ) {
    $env3->{HTTP_COOKIE} = "simple_session=$1";
}

cmpthese(timethese(0,{
    'app1_simple' => sub {
        $app->($env);
    },
    'app2_plack' => sub {
        $app2->($env2);
    },
    'app3_simple_empty' => sub {
        $app3->($env3);
    }
}));

say stringf([$env->{HTTP_COOKIE},$app->($env)]);
say stringf([$env2->{HTTP_COOKIE}, $app2->($env2)]);
say stringf([$env3->{HTTP_COOKIE}, $app3->($env3)]);


