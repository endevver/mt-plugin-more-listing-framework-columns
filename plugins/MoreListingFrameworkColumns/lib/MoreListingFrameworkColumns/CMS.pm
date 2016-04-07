package MoreListingFrameworkColumns::CMS;

use strict;
use warnings;
use MT::Util qw( encode_html );
use Scalar::Util qw( blessed );
use Try::Tiny;

use DDP { output => 'stderr', return => 'pass', caller_info => 1, deparse => 1};
use CustomFields::Util; #DDP

sub debug_fields {
    my $field = shift;
    return 0;
    $field = blessed($field) ? $field->basename : $field||'';
    return $field =~ m{(featured|has_video|related_link1)} ? 1 : 0;
}

# Update all of the listing framework screens to include filters that any user
# has created, not just the filters the current user created.
sub list_template_param {
    my ($cb, $app, $param, $tmpl) = @_;
    my $type = $param->{object_type};

    my $filters = build_filters( $app, $type, encode_html => 1 );

    require JSON;
    my $json = JSON->new->utf8(0);

    # Update the parameters with the new filters.
    $param->{filters}     = $json->encode($filters);
    $param->{filters_raw} = $filters;

}

# Listing screen .js calls mode=filtered_list (MT::CMS::Common::filtered_list),
#   which overwrites .js filter list created in list_template_param sub above
# Update .js data structure on listing framework screens to include filters
#   that any user has created, not just the filters the current user created.
sub cms_filtered_list_param {
    my ( $cb, $app, $param, $objs ) = @_;

    my $q = $app->param;
    my $type = $q->param('datasource');

    # Update .js data structure with the new filters.
    my $filters = build_filters( $app, $type, encode_html => 1 );
    $param->{filters} = $filters;
}

sub list_properties {
    my $app = MT->instance;

    CustomFields::Util::load_meta_fields(); #DDP

    my $menu = {
        # Activity Log
        log => {
            id => {
                label   => 'ID',
                display => 'optional',
                order   => 1,
                base    => '__virtual.id',
                auto    => 1,
            },
            class => {
                label   => 'Class',
                order   => 1001,
                display => 'optional',
                auto    => 1,
            },
            category => {
                label   => 'Category',
                order   => 1002,
                display => 'optional',
                auto    => 1,
            },
            level => {
                label   => 'Level',
                order   => 1003,
                display => 'optional',
                auto    => 1,
            },
            metadata => {
                label   => 'Metadata',
                order   => 1004,
                display => 'optional',
                auto    => 1,
            },
            # MT has a definition for the "By" column but it's forced on by
            # default, which is not necessarily useful.
            by => {
                display => 'default',
            },
        },
        # Comment
        comment => {
            id => {
                label   => 'ID',
                display => 'optional',
                order   => 1,
                base    => '__virtual.id',
                auto    => 1,
            },
            # MT has the definition to show the IP address already, but for
            # whatever reason it's only to be displayed if the
            # `ShowIPInformation` config directive is enabled. So, just
            # override that.
            ip => {
                # condition => sub { MT->config->ShowIPInformation },
                condition => 1,
            },
            url => {
                label   => 'Commenter URL',
                order   => 301,
                display => 'optional',
                auto    => 1,
                html    => \&url_link,
            },
            email => {
                label   => 'Commenter Email',
                order   => 302,
                display => 'optional',
                auto    => 1,
            },
            # This has been defined already and is the Entry/Page column, used
            # to show a link to the Edit Entry/Edit Page screen for the
            # associated entry/page. We want to add to this, to show a
            # published page link, too.
            entry => {
                bulk_html => sub {
                    my $prop = shift;
                    my ( $objs, $app ) = @_;
                    my %entry_ids = map { $_->entry_id => 1 } @$objs;
                    my @entries
                        = MT->model('entry')
                        ->load( { id => [ keys %entry_ids ], },
                        { no_class => 1, } );
                    my %entries = map { $_->id => $_ } @entries;
                    my @result;

                    for my $obj (@$objs) {
                        my $id    = $obj->entry_id;
                        my $entry = $entries{$id};
                        if ( !$entry ) {
                            push @result, MT->translate('Deleted');
                            next;
                        }

                        my $type = $entry->class_type;
                        my $img
                            = MT->static_path
                            . 'images/nav_icons/color/'
                            . $type . '.gif';
                        my $title_html
                            = MT::ListProperty::make_common_label_html( $entry,
                            $app, 'title', 'No title' );

                        my $permalink = $entry->permalink;
                        my $view_img
                            = MT->static_path . 'images/status_icons/view.gif';
                        my $view_link_text
                            = MT->translate( 'View [_1]', $entry->class_label );
                        my $view_link = $entry->status == MT::Entry::RELEASE()
                            ? qq{
                            <span class="view-link">
                              <a href="$permalink" target="_blank">
                                <img alt="$view_link_text" src="$view_img" />
                              </a>
                            </span>
                        }
                            : '';

                        push @result, qq{
                            <span class="icon target-type $type">
                              <img src="$img" />
                            </span>
                            $title_html
                            $view_link
                        };
                    }
                    return @result;
                },
            },
        },
        # Authors
        author => {
            id => {
                label   => 'ID',
                display => 'optional',
                order   => 1,
                base    => '__virtual.id',
                auto    => 1,
                # MT::Author sets empty 'view' scope for 'id' column, which
                # disables its display at any scope (system, website, blog).
                view    => [ 'system' ],
            },
            basename => {
                label   => 'Basename',
                order   => 1001,
                display => 'optional',
                auto    => 1,
            },
            preferred_language => {
                label   => 'Preferred Language',
                order   => 1002,
                display => 'optional',
                auto    => 1,
            },
            page_count => {
                label        => 'Pages',
                filter_label => '__PAGE_COUNT',
                display      => 'optional',
                order        => 301,
                base         => '__virtual.object_count',
                col_class    => 'num',
                count_class  => 'page',
                count_col    => 'author_id',
                # Pages don't have an `author_id` filter type by default.
                # 'author_id' filter type for Pages is defined below.
                filter_type  => 'author_id',
            },
            lockout => {
                display   => 'optional',
                # Generate content to be displayed in table cells for 'lockout'
                # column because 'lockout' is not a real author field.
                raw       => sub {
                    my $prop = shift;
                    my ( $obj, $app, $opts ) = @_;
                    return $obj->locked_out
                    ? '* ' . MT->translate('Locked Out') . ' *'
                    : MT->translate('Not Locked Out');
                },
                # Sort users on locked_out: 1 = Locked out; 0 = Not locked out
                # Reverse direction of sort so locked out users are displayed
                # first when 'Lockout' column is clicked the first time.
                bulk_sort => sub {
                    my $prop = shift;
                    my ($objs) = @_;
                    return sort { $b->locked_out <=> $a->locked_out } @$objs;
                },
            },
        },
        # Pages - Define 'author_id' filter type for Pages
        page => {
            author_id => {
                base            => 'entry.author_id',
                label_via_param => sub {
                    my $prop = shift;
                    my ( $app, $val ) = @_;
                    my $author = MT->model('author')->load($val);
                    return MT->translate( 'Pages by [_1]', $author->nickname, );
                },
            },
        },
        # Commenters, really just a subset of Authors
        commenter => {
            basename => {
                label   => 'Basename',
                order   => 1001,
                display => 'optional',
                auto    => 1,
            },
            preferred_language => {
                label   => 'Preferred Language',
                order   => 1002,
                display => 'optional',
                auto    => 1,
            },
        },
        # Assets
        asset => {
            class => {
                display => 'optional',
                order   => 201,
            },
            description => {
                display => 'optional',
                order   => 300,
            },
            url => {
                label   => 'URL',
                display => 'optional',
                order   => 400,
                auto    => 1,
                html    => \&url_link,
            },
            file_path => {
                label   => 'File Path',
                display => 'optional',
                order   => 401,
                auto    => 1,
            },
            file_name => {
                display => 'optional',
                order   => 402,
            },
            file_ext => {
                display => 'optional',
                order   => 403,
            },
            image_width => {
                display => 'optional',
                order   => 501,
            },
            image_height => {
                display => 'optional',
                order   => 502,
            },
            appears_in => {
                label   => 'Appears In...',
                display => 'optional',
                order   => 600,
                html    => sub {
                    my ( $prop, $obj, $app ) = @_;

                    # Find any asset-entry (or asset-page) associations.
                    my @objectassets = $app->model('objectasset')->load({
                        asset_id => $obj->id,
                    });

                    my $html = '';
                    foreach my $objectasset (@objectassets) {
                        my $ds = $objectasset->object_ds;
                        # Try to load the associated object.
                        if (
                            $app->model( $ds )
                                ->exist( $objectasset->object_id )
                        ) {
                            my $assetobject = $app->model( $ds )
                                ->load( $objectasset->object_id );

                            # If this is an Entry or Page, build the edit and
                            # view links.
                            if ( $ds eq 'entry' || $ds eq 'page' ) {
                                my $type = $assetobject->class_type;
                                my $img
                                    = $app->static_path
                                    . 'images/nav_icons/color/'
                                    . $type . '.gif';
                                my $title_html
                                    = MT::ListProperty::make_common_label_html(
                                        $assetobject, $app, 'title', 'No title'
                                    );

                                my $permalink = $assetobject->permalink;
                                my $view_img = $app->static_path
                                    . 'images/status_icons/view.gif';
                                my $view_link_text = MT->translate(
                                    'View [_1]',
                                    $assetobject->class_label
                                );
                                my $view_link = $assetobject->status == MT::Entry::RELEASE()
                                    ? qq{
                                    <span class="view-link">
                                      <a href="$permalink" target="_blank">
                                        <img alt="$view_link_text" src="$view_img" />
                                      </a>
                                    </span>
                                }
                                    : '';

                                $html .= qq{
                                    <p>
                                        <span class="icon target-type $type">
                                          <img src="$img" />
                                        </span>&nbsp;$title_html&nbsp;$view_link
                                    </p>
                                };
                            }
                            # Not an Entry or Page association.
                            else {
                                $html .= MT::ListProperty::make_common_label_html(
                                    $assetobject, $app, 'label', 'No label'
                                );
                            }
                        }
                    }

                    return $html;
                },
            },
        },
        # Blog
        blog => {
            description => {
                label   => 'Description',
                display => 'optional',
                order   => 200,
                auto    => 1,
            },
            site_path => {
                label   => 'Site Path',
                display => 'optional',
                order   => 275,
                auto    => 1,
            },
            site_url => {
                label   => 'Site URL',
                display => 'optional',
                order   => 276,
                auto    => 1,
                html    => \&url_link,
            },
            archive_path => {
                label   => 'Archive Path',
                display => 'optional',
                order   => 277,
                auto    => 1,
            },
            archive_url => {
                label   => 'Archive URL',
                display => 'optional',
                order   => 278,
                auto    => 1,
                html    => \&url_link,
            },
            theme_label => {
                label   => 'Theme',
                display => 'optional',
                order   => 605,
                html    => \&theme_label,
            },
        },
        # Website
        website => {
            description => {
                label   => 'Description',
                display => 'optional',
                order   => 200,
                auto    => 1,
            },
            site_path => {
                label   => 'Site Path',
                display => 'optional',
                order   => 275,
                auto    => 1,
            },
            site_url => {
                label   => 'Site URL',
                display => 'optional',
                order   => 276,
                auto    => 1,
                html    => \&url_link,
            },
            archive_path => {
                label   => 'Archive Path',
                display => 'optional',
                order   => 277,
                auto    => 1,
            },
            archive_url => {
                label   => 'Archive URL',
                display => 'optional',
                order   => 278,
                auto    => 1,
                html    => \&url_link,
            },
            theme_label => {
                label   => 'Theme',
                display => 'optional',
                order   => 605,
                html    => \&theme_label,
            },
        },
        # Custom Fields
        field => {
            id => {
                label   => 'ID',
                display => 'optional',
                order   => 1,
                base    => '__virtual.id',
                auto    => 1,
            },
            name => {
                sub_fields => [
                    # A "Required" icon appears next to the field name. This was
                    # set up in the Commercial.pack already, but for some
                    # reason is not enabled.
                    {
                        class   => 'required',
                        label   => 'Required',
                        display => 'default',
                    },
                    {
                        # `description` is already styled so get around it by
                        # using the shorter `desc`.
                        class   => 'desc',
                        label   => 'Description',
                        display => 'optional',
                    },
                    {
                        class   => 'template_tag',
                        label   => 'Template Tag',
                        display => 'optional',
                    },
                ],
                # Overwrite the existing HTML for the field.
                html => \&cf_name_field,
            },
            # This is the "System Object" column
            obj_type => {
                display => 'optional',
            },
            basename => {
                display => 'optional',
                order   => 500,
            },
            options => {
                label => 'Field Options',
                col   => 'options',
                auto  => 1,
                order => 600,
            },
            default => {
                label => 'Default Value',
                auto  => 1,
                order => 601,
            }
        }
    };

    my $iter     = MT->model('field')->load_iter( undef, { sort => 'name' } );
    my $order    = 10000;
    my $cf_types = $app->registry( 'customfield_types' );
    my %blog_fields;
    # my $spec   = "%-20s %-5s %-5s %-7s %s\n";
    # printf STDERR $spec, "Field", "Show", 'App', 'Field', 'Field blogs';
    while ( my $field = $iter->() ) {

        # Skip field if custom field type is not defined/available
        unless ( $cf_types->{$field->type} ) {
            warn sprintf "Skipping '%s' field due to unknown type '%s'",
                $field->basename, $field->type||'UNDEFINED';
            next;
        }

        my $cf_basename = 'field.' . $field->basename;
        my $DEBUG       = debug_fields( $field );

        # The condition code ref below needs to check the app blog ID against
        # ALL blogs that have a particular field's basename defined. Since
        # we're redefining each hash value, we have to capture each blog ID for
        # comparison. Otherwise, only the blog in the last defined field would
        # be used.
        $blog_fields{$field->basename} ||= [];
        push( $blog_fields{$field->basename}, $field->blog_id );

        # Mapping from column def keywords to basic property types.
        my %AUTO = (
            string    => 'string',
            smallint  => 'integer',
            bigint    => 'integer',
            boolean   => 'single_select',
            datetime  => 'date',
            timestamp => 'date',
            integer   => 'integer',
            text      => 'string',
            float     => 'float',
            ## TBD
            # blob      => '',

            ## Meta
            vchar         => 'string',
            vchar_idx     => 'string',
            vinteger      => 'integer',
            vinteger_idx  => 'integer',
            vdatetime     => 'date',
            vdatetime_idx => 'date',
            vfloat        => 'float',
            vfloat_idx    => 'float',
            vclob         => 'string',
            ## TBD
            # vblob         => '',
        );

        # require MT::Meta;
        my %meta;
        my $id        = $cf_basename;
        my $obj_type  = $field->obj_type;
        my $obj_class = $app->model($obj_type);
            my $def;
        $meta{base} = '__virtual.integer' if $field->basename =~ m{featured};
        # $meta{meta_col} = $cf_types->{$field->type}{column_def};
        # $meta{is_meta} = 1;
        # my $auto_type   = $AUTO{$meta{meta_col}}
        #     or die MT->translate(
        #     'Failed to initialize auto list property [_1].[_2]: unsupported column type.',
        #     $obj_class, $id
        #     );
        $meta{col} = $field->basename;
        # $meta{_base} = MT::ListProperty->instance( '__virtual', $auto_type );

        # $menu->{ $field->obj_type }->{ $cf_basename } =
        $menu->{ $field->obj_type }->{ $field->basename } = {
            %meta,
            label   => $field->name,
            display => 'optional',
            order   => $order++,
            condition => sub {
                my ( $prop ) = @_;
                my $show     = 0;
                my $blog_id  = $field->blog_id;
                my @blogs    = @{ $blog_fields{$field->basename} };
                my ( $app_blog, $is_website ) = try {
                    my $a = $app->blog;
                    ( $a->id, ( $a->class eq 'website' ? 1 : 0 ) );
                };

                # Show the field if showing system overview (no app blog),
                # OR it's a system-wide field (no field blog_id),
                # OR the app blog is the same as any of the field's blogs
                if (   !$app_blog || !$blog_id
                    or grep { $app_blog == $_ } @blogs ) {
                    $show = 1;
                }
                # OR if showing the website level of any of the field's blogs
                elsif ( $is_website ) {
                    my $Blog         = $app->model('blog');
                    my $args         = { fetchonly => ['parent_id'] };
                    my @parent_blogs = map {
                            $Blog->load( { id => $_ }, $args )->parent_id
                        } @blogs;
                    $show = scalar grep { $app_blog == $_ } @parent_blogs;
                }

                # debug_fields( $field )
                #     and printf STDERR $spec,
                #         $field->basename, ($show ? 'YES' : 'NO'),
                #         $app_blog,        $field->blog_id, join(', ', @blogs );

                return $show;

            },
            html    => sub {
                my ( $prop, $obj, $app ) = @_;

                # Load the data and return the field value. If there is no
                # value, just return an empty string -- otherwise, "null" is
                # returned.
                return $obj->$cf_basename
                    || '';
            },
            filter_tmpl => '<mt:var name="filter_form_string">',
            grep => sub {
                my $prop = shift;
                my ( $args, $objs, $opts ) = @_;
                my $option = $args->{option};
                my $query  = $args->{string};

                $DEBUG and say STDERR sprintf "#### RUNNING FILTER GREP ON FIELD %s: %s", $prop->{id}, np(%{{ option => $option, string => $query, objs => $objs, opts => $opts }});

                my @result = grep {
                    filter_custom_field({
                        option => $option,
                        query  => $query,
                        field  => $_->$cf_basename,
                    })
                } @$objs;

                $DEBUG and say STDERR scalar(@result)." results from grep filter: ".np(@result);
                return @result;
            },
            # Make the column sortable
            bulk_sort => sub {
                my $prop = shift;
                my ($objs, $opts) = @_;
                return sort {
                    $a->$cf_basename cmp $b->$cf_basename
                } @$objs;
            },
        };

        # # DDP
        if ( $DEBUG ) {
            say STDERR sprintf '%s::list_properties: Adding list property for %s and %s field for blog_id %d: %s',
            __PACKAGE__, $field->basename, $cf_basename, $field->blog_id, np($menu->{ $field->obj_type }->{ $field->basename });
        }
    }

    return $menu;
}

# Build a clickable link to the URL supplied in whatever column this function
# is called from.
sub url_link {
    my ( $prop, $obj, $app ) = @_;
    my $url = $prop->col;
    return '<a href="' . $obj->$url . '" target="_blank">' . $obj->$url . '</a>';
}

sub theme_label {
    my ( $prop, $obj, $app ) = @_;
    my $id = $obj->theme_id
        or return '<em>No theme applied</em>';

    # look for registry.
    my $registry = MT->registry('themes');
    require MT::Theme;
    my $theme = MT::Theme->_load_from_registry( $id, $registry->{$id} );

    ## if not exists in registry, going to look for theme directory.
    $theme = MT::Theme->_load_from_themes_directory($id)
        unless defined $theme;

    ## at last, search for template set.
    $theme = MT::Theme->_load_pseudo_theme_from_template_set($id)
        unless defined $theme;

    return defined $theme && $theme->registry('label')
        ? $theme->registry('label')
        : "Failed to load theme: $id";
}

# Filter custom fields with the specified text and option. This isn't perfect;
# it's really focused on parsing strings. Other, more complext, types of CF data
# probably can't be well-filtered by this basic capability.
sub filter_custom_field {
    my ($arg_ref) = @_;
    my $option = $arg_ref->{option};
    my $query  = $arg_ref->{query};
    my $field  = $arg_ref->{field};

    my $result;
    if ( 'equal' eq $option ) {
        $result = $field =~ /^$query$/;
    }
    if ( 'contains' eq $option ) {
        $result =  $field =~ /$query/i;
    }
    elsif ( 'not_contains' eq $option ) {
        $result =  $field !~ /$query/i;
    }
    elsif ( 'beginning' eq $option ) {
        $result =  $field =~ /^$query/i;
    }
    elsif ( 'end' eq $option ) {
        $result =  $field =~ /$query$/i;
    }
    say STDERR sprintf '##### filter_custom_field result: %s. %s', $result, np($arg_ref) if debug_fields($field);
}

# From MT::CMS::Filter
# Saved filters should be available for all users. Below, the filter model load
# should not be restricted to the user that created it.
sub build_filters {
    my ( $app, $type, %opts ) = @_;
    my $obj_class = MT->model($type);

    # my @user_filters = MT->model('filter')
    #     ->load( { author_id => $app->user->id, object_ds => $type } );
    my @user_filters = MT->model('filter')
        ->load( { object_ds => $type } );

    @user_filters = map { $_->to_hash } @user_filters;

    my @sys_filters;
    my $sys_filters = MT->registry( system_filters => $type );
    for my $sys_id ( keys %$sys_filters ) {
        next if $sys_id =~ /^_/;
        my $sys_filter = MT::CMS::Filter::system_filter( $app, $type, $sys_id )
            or next;
        push @sys_filters, $sys_filter;
    }
    @sys_filters = sort { $a->{order} <=> $b->{order} } @sys_filters;

    #FIXME: Is this always right path to get it?
    my @legacy_filters;
    my $legacy_filters
        = MT->registry( applications => cms => list_filters => $type );
    for my $legacy_id ( keys %$legacy_filters ) {
        next if $legacy_id =~ /^_/;
        my $legacy_filter = MT::CMS::Filter::legacy_filter( $app, $type, $legacy_id )
            or next;
        push @legacy_filters, $legacy_filter;
    }

    my @filters = ( @user_filters, @sys_filters, @legacy_filters );
    for my $filter (@filters) {
        my $label = $filter->{label};
        if ( 'CODE' eq ref $label ) {
            $filter->{label} = $label->();
        }
        if ( $opts{encode_html} ) {
            MT::Util::deep_do(
                $filter,
                sub {
                    my $ref = shift;
                    $$ref = MT::Util::encode_html($$ref);
                }
            );
        }
    }
    return \@filters;
}

# The Custom Field "Name" field can be used to display lots of pertinent
# information.
sub cf_name_field {
    my ( $prop, $obj, $app ) = @_;
    my $name = MT::Util::encode_html($obj->name);
    my $tag  = MT::Util::encode_html($obj->tag);
    my $current_blog_id = $app->param('blog_id') || 0;
    my $blog_id = $obj->blog_id || 0;
    my $scope_html;

    if ( !$current_blog_id || $blog_id != $current_blog_id ) {
        my $scope = 'System';
        if ( $blog_id > 0 ) {
            my $blog = MT->model('blog')->load($blog_id);
            $scope = $blog->is_blog ? 'Blog' : 'Website';
        }
        my $scope_lc = lc $scope;
        my $scope_label = MT->translate($scope);
        $scope_html = qq{
            <span class="cf-scope $scope_lc sticky-label">$scope_label</span>
        };
    }

    my $required_label = MT->translate("Required");
    my $required = $obj->required
        ? qq{<span class="required sticky-label">$required_label</span>}
        : q{};

    my $desc = $obj->description
        ? '<div class="desc" style="margin-bottom: 5px;">' . $obj->description . '</div>'
        : '';

    my $code = '<div class="template_tag">Template tag: <code class="code">&lt;mt:'
        . $tag . ' /&gt;</code></div>';

    my $user = $app->user;
    if ( $user->is_superuser
         || $user->permissions($obj->blog_id)->can_do('administer_blog') )
    {
        my $edit_link = $app->uri(
            mode => 'view',
            args => {
                _type   => 'field',
                id      => $obj->id,
                blog_id => $obj->blog_id,
            }
        );
        return qq{
            $scope_html <a href="$edit_link">$name</a> $required $desc $code
        };
    } else {
        return "$scope_html $name $required $desc $code";
    }
}

1;

__END__

customfield_types
Printing in line 111 of plugins/gWizMobile/t/40-endpoint-featured.t:
[
    [0]  "embed",
    [1]  "entry",
    [2]  "checkbox",
    [3]  "reciprocal_entry",
    [4]  "photo",
    [5]  "file",
    [6]  "reciprocal_page",
    [7]  "selected_entries",
    [8]  "url",
    [9]  "post_type",
    [10] "selected_content",
    [11] "genentech_linked_media",
    [12] "selected_comments",
    [13] "video",
    [14] "selected_assets",
    [15] "radio_input",
    [16] "checkbox_group",
    [17] "wysiwyg_textarea",
    [18] "gamify_badges_summary",
    [19] "selected_asset.files",
    [20] "gamify_points_summary",
    [21] "datetime",
    [22] "audio",
    [23] "multi_use_single_line_text_group",
    [24] "text",
    [25] "selected_asset.images",
    [26] "select",
    [27] "selected_asset.videos",
    [28] "selected_asset.photos",
    [29] "multi_use_timestamped_multi_line_text",
    [30] "poll_position",
    [31] "selected_asset.audios",
    [32] "radio",
    [33] "image",
    [34] "message",
    [35] "gamify_badges_chooser",
    [36] "selected_pages",
    [37] "textarea"
]
