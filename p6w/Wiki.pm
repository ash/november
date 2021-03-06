use v6;

use CGI;
use HTML::Template;
use Text::Markup::Wiki::Minimal;

sub file_exists( $file ) {
    # RAKUDO: use ~~ :e
    my $exists = False;
    try {
        my $fh = open( $file );
        $exists = True;
    }
    return $exists;
}

sub get_unique_id {
    # hopefully pretty unique ID
    return int(time%1000000/100) ~ time%100
}

sub r_remove( $str is rw ) {
    # RAKUDO: :g not implemented yet :( 
    while $str ~~ /\\r/ {
        $str = $str.subst( /\\r/, '' );
    }
}

sub tags_parse ($tags) {
    # RAKODO: we need regexp in split [perl 57378]
    # my @tags = $tags.split(/ \s* , \s* /)
    # workaround:
    my @tags = $tags.split(',');
    @tags = map { .subst(/ ^ \s+ /, '') }, @tags;
    @tags = map { .subst(/  \s+ $ /, '') }, @tags;

    @tags = map { .subst(/ \n /, '') }, @tags;
    return @tags;
}


sub tag_count_normalize ($count) {
    # TODO: log need here, faking it for now
    if $count < 10 {
        return $count; 
    }
    else {
        return 10; 
    }
}

role Session {
    has $.sessionfile_path  is rw;
    has $.sessions          is rw;

    method init {
        # RAKUDO: set the attributes when declaring them
        $.sessionfile_path = 'data/sessions';
    }

    method add_session( $id, %stuff) {
        my $sessions = self.read_sessions();
        $sessions{$id} = %stuff;
        self.write_sessions($sessions);
    }

    method remove_session($id) {
        my $sessions = self.read_sessions();
        $sessions.delete($id);
        self.write_sessions($sessions);
    }

    method read_sessions {
        return {} unless file_exists( $.sessionfile_path );
        my $string = slurp( $.sessionfile_path );
        my $stuff = eval( $string );
        return $stuff;
    }

    method write_sessions( $sessions ) {
        my $fh = open( $.sessionfile_path, :w );
        $fh.say( $sessions.perl );
        $fh.close;
    }

    method new_session($user_name) {
        my $session_id = get_unique_id();
        self.add_session( $session_id, { user_name => $user_name } );
        return $session_id;
    }
}

class Storage {
    method wiki_page_exists($page)                               { ... }

    method read_recent_changes()                                 { ... }
    method write_recent_changes( $recent_changes )               { ... }

    method read_page_history($page)                              { ... }
    method write_page_history( $page, $page_history )            { ... }

    method read_modification($modification_id)                   { ... }
    method write_modification( $modification_id, $modification ) { ... }

    method read_page_tags ($page)                                { ... }
    method write_page_tags ($page, $tags)                        { ... }

    method add_tags ($page, $tags)                               { ... }
    method remove_tags ($page, $tags)                            { ... }

    method read_tags_count                                       { ... }
    method write_tags_count (Hash $count)                        { ... }

    method read_tags_index                                       { ... }
    method write_tags_index (Hash $index)                        { ... }

    method get_tag_count ($page)                                { ... }


    method save_page($page, $new_text, $author, $tags) {
        my $modification_id = get_unique_id();

        my $page_history = self.read_page_history($page);
        $page_history.unshift( $modification_id );
        self.write_page_history( $page, $page_history );

        self.write_modification( $modification_id, 
                                 [ $page, $new_text, $author] );
        
        my $old_tags = self.read_page_tags($page); 
        self.remove_tags($page, $old_tags);
        self.add_tags($page, $tags);

        self.write_page_tags($page, $tags);
    }

    method add_recent_change( $modification_id ) {
        my $recent_changes = self.read_recent_changes();
        $recent_changes.unshift($modification_id);
        self.write_recent_changes( $recent_changes );
    }

    method read_page($page) {
        my $page_history = self.read_page_history($page);
        return "" unless $page_history;
        my $latest_change = self.read_modification( $page_history.shift );
        return $latest_change[1];
    }
}

class Storage::File is Storage {
    my $.content_path        is rw;
    my $.modifications_path  is rw;
    my $.recent_changes_path is rw;
    my $.page_tags_path      is rw;
    my $.tags_count_path     is rw;
    my $.tags_index_path     is rw;

    method init {
        $.content_path = 'data/articles/';
        $.modifications_path = 'data/modifications/';
        $.recent_changes_path = 'data/recent-changes';
        $.page_tags_path = 'data/page_tags/';
        $.tags_count_path = 'data/tags_count';
        $.tags_index_path = 'data/tags_index';
    }

    method wiki_page_exists($page) {
        return file_exists( $.content_path ~ $page );
    }

    method read_recent_changes {
        return [] unless file_exists( $.recent_changes_path );
        return eval( slurp( $.recent_changes_path ) );
    }

    method write_recent_changes ( $recent_changes ) {
        my $fh = open($.recent_changes_path, :w);
        $fh.say($recent_changes.perl);
        $fh.close;
    }

    method read_page_history($page) {
        my $file = $.content_path ~ $page;
        return [] unless file_exists( $file );
        my $page_history = eval( slurp($file) );
        return $page_history;
    }

    method write_page_history( $page, $page_history ) {
        my $file = $.content_path ~ $page;
        my $fh = open($file, :w);
        $fh.say( $page_history.perl );
        $fh.close;
    }

    method read_modification($modification_id) {
        my $file = $.modifications_path ~ $modification_id;
        # RAKUDO: use :e
        return [] unless file_exists( $file );
        return eval( slurp($file) );
    }

    method write_modification ( $modification_id, $modification ) {
        my $data = $modification.perl;
        r_remove($data);

        my $file =  $.modifications_path ~ $modification_id;
        my $fh = open( $file, :w );
        $fh.say( $data );
        $fh.close();
    }

    method add_tags ($page, $tags) {

        # RAKUDO: return with modificaton parsed wrong
        return 1 if $tags ~~ m/^ \s* $/;
        my $count = self.read_tags_count;

        my @tags = tags_parse($tags);
        for @tags -> $t {
            # RAKUDO: Increment not implemented in class 'Undef'
            if $count{$t} {
                $count{$t}++;
            } 
            else {
                $count{$t} = 1;
            }
        }

        self.write_tags_count($count);

        my $index = self.read_tags_index;

        for @tags -> $t {
            # I think it`s must be Hash of Arrays, but right now look like 
            # with Hash of Hashes it`s simply to realize.
            unless $index{$t} {
                $index{$t} = {};
            }
            unless $index{$t}{$page} {
                $index{$t}{$page} = 1;
            }

        }

        self.write_tags_index($index);
    }

    method remove_tags($page, $tags) {
        
        # RAKUDO: return with modificaton parsed wrong
        return 1 if $tags ~~ m/^ \s* $/;

        my $count = self.read_tags_count;

        my @tags = tags_parse($tags);
        for @tags -> $t {
            # RAKUDO: Decrement not implemented in class 'Undef'
            if $count{$t} && $count{$t} > 0 {
                $count{$t}--;
            } 
            else {
                $count{$t} = 0;
            }
        }

        self.write_tags_count($count);

        my $index = self.read_tags_index;

        for @tags -> $t {
            # I think it`s must be Hash of Arrays, but right now look like with
            # Hash of Hashes it`s simply to realize.
            if $index{$t} && $index{$t}{$page} {
                    $index{$t}{$page} = 0;
            }
        }
        self.write_tags_index($index);
    }

    method read_page_tags($page) {
        my $file = $.page_tags_path ~ $page;
        # RAKUDO: use :e
        return '' unless file_exists( $file );
        return slurp($file);
    }

    method write_page_tags ($page, $tags) {
        my $file =  $.page_tags_path ~ $page;
        my $fh = open( $file, :w );
        $fh.say( $tags );
        $fh.close();
    }
   
    method read_tags_count {
        my $file = $.tags_count_path;
        # RAKUDO: use :e
        return {} unless file_exists($file);
        return eval( slurp($file) );
    }

    method write_tags_count (Hash $counts) {
        my $file =  $.tags_count_path;
        my $fh = open( $file, :w );
        $fh.say( $counts.perl );
        $fh.close();
    }

    method read_tags_index {  
        my $file = $.tags_index_path;
        # RAKUDO: use :e
        return {} unless file_exists($file);
        return eval( slurp($file) );
    }

    method write_tags_index (Hash $index) {
        my $file =  $.tags_index_path;
        my $fh = open( $file, :w );
        $fh.say( $index.perl );
        $fh.close();
    }

    method get_tag_count ($tag)  {
        my $counts = self.read_tags_count;
        return $counts{$tag};
    }
}

class Wiki does Session {

    my $.template_path       is rw;
    my $.userfile_path       is rw;

    has Storage $.storage    is rw;
    has CGI     $.cgi        is rw;

    method init {
        # RAKUDO: set the attributes when declaring them
        $.template_path = 'skin/';
        $.userfile_path = 'data/users';

        # Multiple dispatch doesn't work
        $.storage = Storage::File.new();
        $.storage.init();
        #Storage::File::init(self);
        Session::init(self);
    }

    method handle_request(CGI $cgi) {
        $.cgi = $cgi;

        my $action = $cgi.param<action> // 'view';

        # Maybe we should consider turning this given into a lookup hash.
        # RAKUDO: 'when' doesn't break out by default yet, #57652
        given $action {
            when 'view'           { self.view_page();           return; }
            when 'edit'           { self.edit_page();           return; }
            when 'log_in'         { self.log_in();              return; }
            when 'log_out'        { self.log_out();             return; }
            when 'recent_changes' { self.list_recent_changes(); return; }
        }

        self.not_found();
    }

    method view_page() {
        my $page = $.cgi.param<page> // 'Main_Page';

        unless $.storage.wiki_page_exists($page) {
            self.not_found;
            return;
        }

        my $template = HTML::Template.new(
            filename => $.template_path ~ 'view.tmpl');

        $template.param('TITLE'     => $page);
        $template.param('CONTENT'   => Text::Markup::Wiki::Minimal.new.format(
                                           $.storage.read_page($page),
                                           { self.make_link($^page) }
                                       ));

        my $page_tags = $.storage.read_page_tags($page);
        my @page_tags = tags_parse($page_tags); 

        # does exist clearest way to check @tags... mb @t ~~ [] ?
        if @page_tags[0] {
            @page_tags = map { '<a class="t' ~ $.storage.get_tag_count($_) 
                ~ '" href="?action=toc?tag=' ~ $_ ~'">' ~ $_ ~ '</a>'}, @page_tags;

            $page_tags = @page_tags.join(', ');
        }
    
        $template.param('PAGETAGS' => $page_tags);

        my $tags = $.storage.read_tags_count;

        my $tags_str;
        if $tags {
            for $tags.keys -> $tag {
                if $tags{$tag} > 0 {
                    $tags_str = $tags_str ~ '<a class="t' 
                        ~ tag_count_normalize( $tags{$tag} ) 
                        ~ '" href="?action=toc?tag=' ~ $tag ~ '">' 
                        ~ $tag ~ '</a> ';
                }
            }
        }
        $template.param('TAGS' => $tags_str);

        $template.param('LOGGED_IN' => self.logged_in());

        $.cgi.send_response(
            $template.output(),
        );
    }

    method logged_in() {
        my $sessions = self.read_sessions();
        my $session_id = $.cgi.cookie<session_id>;
        # RAKUDO: 'defined' should maybe be 'exists', although here it doesn't
        # matter.
        defined $session_id && defined $sessions{$session_id}
    }

    method edit_page() {
        my $page = $.cgi.param<page> // 'Main_Page';

        my $sessions = self.read_sessions();

        return self.not_authorized() unless self.logged_in();

        my $already_exists
                        = $.storage.wiki_page_exists($page);
        my $action      = $already_exists ?? 'Editing' !! 'Creating';
        my $old_content = $already_exists ?? $.storage.read_page($page) !! '';
        my $title = "$action $page";

        # The 'edit' action handles both showing the form and accepting the
        # POST data. The difference is the presence of the 'articletext'
        # parameter -- if there is one, the action is considered a save.
        if $.cgi.param<articletext> || $.cgi.param<tags> {
            my $new_text = $.cgi.param<articletext>;
            my $tags = $.cgi.param<tags>;
            my $session_id = $.cgi.cookie<session_id>;
            my $author = $sessions{$session_id}<user_name>;
            $.storage.save_page($page, $new_text, $author, $tags);
            return self.view_page();
        }

        my $template = HTML::Template.new(
            filename => $.template_path ~ 'edit.tmpl');

        $template.param('PAGE'      => $page);
        $template.param('TITLE'     => $title);
        $template.param('CONTENT'   => $old_content);

        $template.param('TAGS'      => $.storage.read_page_tags($page));
        $template.param('LOGGED_IN' => True);

        $.cgi.send_response(
            $template.output(),
        );
    }

    method not_authorized() {
        my $template = HTML::Template.new(
            filename => $.template_path ~ 'action_not_authorized.tmpl');

        # TODO: file bug, without "'" it is interpreted as named args and not
        #       as Pair
        $template.param('DISALLOWED_ACTION' => 'edit pages');

        $.cgi.send_response(
            $template.output(),
        );

        return;
    }

    method read_users {
        # RAKUDO: use :e
        return {} unless file_exists( $.userfile_path );
        return eval( slurp( $.userfile_path ) );
    }

    method not_found() {
        my $template = HTML::Template.new(
            filename => $.template_path ~ 'not_found.tmpl');

        $template.param('PAGE'      => 'Action Not found');
        $template.param('LOGGED_IN' => self.logged_in());

        $.cgi.send_response(
            $template.output(),
        );
        return;
    }

    method log_in {
        if my $user_name = $.cgi.param<user_name> {

            my $password = $.cgi.param<password>;

            my %users = self.read_users();

            # Yes, this is cheating. Stand by for a real MD5 hasher.
            if (defined %users{$user_name} 
               and $password eq %users{$user_name}<plain_text>) {
#            if Digest::MD5::md5_base64(
#                   Digest::MD5::md5_base64($user_name) ~ $password
#               ) eq %users{$user_name}<password> {

                my $session_id = self.new_session($user_name);
                my $session_cookie = "session_id=$session_id";

                my $template = HTML::Template.new(
                    filename => $.template_path ~ 'login_succeeded.tmpl');

                $.cgi.send_response(
                    $template.output(),
                    { cookie => $session_cookie }
                );

                return;
            }

            my $template = HTML::Template.new(
                filename => $.template_path ~ 'login_failed.tmpl');

            $.cgi.send_response(
                $template.output(),
            );

            return;
        }

        my $template = HTML::Template.new(
            filename => $.template_path ~ 'log_in.tmpl');

        $.cgi.send_response(
            $template.output(),
        );

        return;
    }

    method log_out {
        if defined $.cgi.cookie<session_id> {

            my $session_id = $.cgi.cookie<session_id>;
            self.remove_session( $session_id );

            my $session_cookie = "session_id=";

            my $template = HTML::Template.new(
                filename => $.template_path ~ 'logout_succeeded.tmpl');

            $.cgi.send_response(
                $template.output(),
                { :cookie($session_cookie) }
            );

            return;
        }

        my $template = HTML::Template.new(
            filename => $.template_path ~ 'logout_succeeded.tmpl');

        $.cgi.send_response(
            $template.output(),
        );

        return;
    }

    method make_link($page) {
        return sprintf('<a href="?action=%s&page=%s"%s>%s</a>',
                       $.storage.wiki_page_exists($page)
                         ?? ('view', $page, '')
                         !! ('edit', $page, ' class="nonexistent"'),
                       $page);
    }

    method list_recent_changes {

        # RAKUDO: Seemingly impossible to get the right number of list
        # containers using an array variable @recent_changes here.
        my $recent_changes = $.storage.read_recent_changes();

        my @changes;
        for $recent_changes.values -> $modification_id {
            my $modification = $.storage.read_modification($modification_id);
            push @changes, {
                'page' => self.make_link($modification[0]),
                'time' => $modification_id,
                'author' => $modification[2] || 'somebody' };
        }

        my $template = HTML::Template.new(
                filename => $.template_path ~ 'recent_changes.tmpl');

        $template.param('CHANGES'   => @changes);
        $template.param('LOGGED_IN' => self.logged_in());

        $.cgi.send_response(
            $template.output()
        );

        return;
    }
}
# vim:ft=perl6
