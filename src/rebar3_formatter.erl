-module(rebar3_formatter).

-export([format/2]).

-type opts() :: #{
    includes => [file:name()],
    macros => epp:macros(),
    encoding => none | epp:source_encoding(),
    paper => pos_integer(),
    ribbon => pos_integer()
}.
-export_type [opts/0].

-spec format(opts(), file:filename_all()) -> ok.
format(File, Opts) ->
    rebar_api:debug("Formatting ~p with ~p", [File, Opts]),
    AST = get_ast(File, Opts),
    Comments = get_comments(File, Opts),
    format(File, AST, Comments, Opts).

get_ast(File, Opts) ->
    Includes = maps:get(includes, Opts, []),
    Macros = maps:get(macros, Opts, []),
    case epp:parse_file(File, Includes, Macros) of
        {ok, AST} ->
            case [Error || {error, Error} <- AST] of
                [] ->
                    AST;
                [Error|_] ->
                    rebar_api:debug("Couldn't parse ~s: ~p", [File, Error]),
                    erlang:error(Error)
            end;
        {error, OpenError} -> erlang:error(OpenError)
    end.

get_comments(File, _Opts) ->
    erl_comment_scan:file(File).

format(File, AST, Comments, Opts) ->
    Hook = none, %% @todo We can insert our code here, if needed
    User = undefined, %% @todo We can insert our data here, if needed
    Paper = maps:get(paper, Opts, 100),
    Ribbon = maps:get(ribbon, Opts, 80),
    Encoding = maps:get(encoding, Opts, latin1),
    FinalFile =
        case maps:get(output_dir, Opts) of
            undefined -> File;
            OutputDir -> filename:join(filename:absname(OutputDir), File)
        end,
    ok = filelib:ensure_dir(FinalFile),
    FormatOpts = [
        {hook, Hook},
        {user, User},
        {paper, Paper},
        {ribbon, Ribbon},
        {encoding, Encoding}
    ],
    FilteredAST = lists:filter(fun is_original/1, AST),
    rebar_api:debug("~s looks like:~n~p", [File, FilteredAST]),
    rebar_api:debug("~s comments are:~n~p", [File, Comments]),
    WithComments =
        erl_recomment:recomment_forms(
            erl_syntax:form_list(FilteredAST), Comments),
    Formatted = erl_prettypr:format(WithComments, FormatOpts),
    rebar_api:debug("~s NOW looks like:~n~p", [File, Formatted]),
    file:write_file(FinalFile, Formatted).

is_original({attribute, 1, file, _}) -> false;
is_original({attribute, [{generated, true} | _], _, _}) -> false;
is_original(_) -> true.
