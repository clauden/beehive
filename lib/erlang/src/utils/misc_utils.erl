-module (misc_utils).
-include ("common.hrl").
-compile (export_all).

-define (ADJECTIVES, [
  "fast", "quick", "clean", "positive", "generous", "silly", "enjoyable", "friendly", "flighty", "handsome", "hot", "adorable", "cool", "cold", "odd"
]).

-define (NOUNS, [
  "giant", "bee", "queenbee", "sound", "music", "honey", "smile", "balloon", "bird", "wind", "dog", "cat", "duck", "moose", "fish", "guitar", "sparrow", "buzz"
]).

-define (LETTERS, "abcdefghijklmnopqrstuvwxyz0123456789").

generate_unique_name(Num) ->
  lists:flatten([
    random_word(?ADJECTIVES),"-",
    random_word(?NOUNS),"-",
    random_word(?LETTERS, Num, [])
  ]).

random_word(_, 0, Acc) -> lists:reverse(Acc);
random_word(List, Length, Acc) ->
  random_word(List, Length - 1, [random_word(List)|Acc]).
  
random_word(List) ->
  lists:nth(random:uniform(erlang:length(List)), List).

% Take a proplist and a name of a shell script, replace the
% variables set in the proplist, write the "new" shell script
% out and run it, while waiting for it
shell_fox(Name, Proplist) -> 
  Tempfile = create_templated_tempfile(Name, Proplist),
  Self = self(),
  
  spawn(fun() -> 
      Port = open_port({spawn, Tempfile}, [exit_status, {cd, file_utils:relative_path("/tmp")}, use_stdio]),
      wait_for_port(Port, Tempfile, Self, [])
    end),
  receive
    {ok, Tempfile, E, Status} -> {E, Status}
  after timer:seconds(60) ->
    {error, timeout}
  end.

% create a temp file templated with the proplist
% This creates a unique
create_templated_tempfile(Name, Proplist) -> create_templated_tempfile(Name, "/tmp", Proplist).
create_templated_tempfile(Name, Dest, Proplist) ->
  Templated = ?TEMPLATE_SHELL_SCRIPT(Name, Proplist),
  Ref = erlang:phash2(make_ref()),
  Tempfile = filename:join([Dest, lists:append([to_list(Ref), ".sh"])]),
  
  % Write to the temp file
  {ok, Fd} = file:open(Tempfile, [write]),
  file:write(Fd, Templated),
  file:close(Fd),
  % Make it executable
  os:cmd(io_lib:format("chmod 0700 ~s", [Tempfile])),
  Tempfile.
  

% Wait (up to 60 seconds) for a response from the shell script
% for a response. Then send the response to the caller
wait_for_port(Port, Tempfile, AppUpdatorPid, Acc) ->
  receive
    {Port, {data, Info}} ->
      wait_for_port(Port, Tempfile, AppUpdatorPid, [Info|Acc]);
    {Port, {exit_status, Status}} ->
      ListofStrings = case io_lib:char_list(Acc) of
        true -> [Acc];
        false -> lists:reverse(Acc)
      end,
      Tokens = string:tokens(string:join(ListofStrings, "\n"), "\n"),
      O = lists:flatten(lists:map(fun(List) ->
        element(1, lists:foldr(fun (X,{As,[]}) -> {As,[X]}; (X,{As,[Y]}) ->
          {[{erlang:list_to_atom(X),Y}|As],[]} end, {[],[]},  string:tokens(List, " "))) end, Tokens)),
      AppUpdatorPid ! {ok, Tempfile, O, Status},
      file:delete(Tempfile);
    E ->
      file:delete(Tempfile),
      E
  after timer:seconds(60) ->
    file:delete(Tempfile),
    ok
  end.

to_list(Bin) when is_binary(Bin) -> erlang:binary_to_list(Bin);
to_list(Atom) when is_atom(Atom) -> erlang:atom_to_list(Atom);
to_list(Float) when is_float(Float) -> erlang:float_to_list(Float);
to_list(Int) when is_integer(Int) -> erlang:integer_to_list(Int);
to_list(List) -> List.

to_atom(Bin) when is_binary(Bin) -> to_atom(erlang:binary_to_list(Bin));
to_atom(List) when is_list(List) -> erlang:list_to_atom(List);
to_atom(Atom) -> Atom.

to_bin(undefined) -> <<"undefined">>;
to_bin(Tuple) when is_tuple(Tuple) -> to_bin(erlang:term_to_binary(Tuple));
to_bin(Atom) when is_atom(Atom) -> to_bin(erlang:atom_to_list(Atom));
to_bin(Int) when is_integer(Int) -> to_bin(erlang:integer_to_list(Int));
to_bin(Float) when is_float(Float) -> to_bin(erlang:float_to_list(Float));
to_bin(List) when is_list(List) -> 
  case io_lib:char_list(List) of
    true -> erlang:list_to_binary(List);
    false -> lists:map(fun(Ele) -> to_bin(Ele) end, List)
  end;
to_bin(Bin) -> Bin.

to_integer(Str) when is_list(Str) -> erlang:list_to_integer(Str);
to_integer(Int) -> Int.

max([]) -> 0;
max([H|T]) -> max(H, T).
max(M, []) -> M;
max(M, [H|L]) when M > H -> max(M, L);
max(_M, [H|L]) -> max(H,L).

% Only choose values that are actually in the proplist
filter_proplist(_Proplist, [], Acc) -> Acc;
filter_proplist(Proplist, [{K,V}|Rest], Acc) ->
  case proplists:is_defined(K, Proplist) of
    false -> filter_proplist(Proplist, Rest, Acc);
    true -> filter_proplist(Proplist, Rest, [{K,V}|Acc])
  end.

new_or_previous_value(_NewProplist, [], Acc) -> Acc;
new_or_previous_value(NewProplist, [{K,V}|Rest], Acc) ->
  case proplists:is_defined(K,NewProplist) of
    true -> 
      NewV = proplists:get_value(K, NewProplist),
      new_or_previous_value(NewProplist, Rest, [{K, NewV}|Acc]);
    false ->
      new_or_previous_value(NewProplist, Rest, [{K, V}|Acc])
  end.

% name of the local node
localnode(Name) ->
  list_to_atom(lists:append([atom_to_list(Name), "@", nodehost(node())])).

% Get the name of the local node
nodehost(Node) ->
  tl(lists:dropwhile(fun (E) -> E =/= $@ end, atom_to_list(Node))).


% Turn the proplists into atoms
atomize([], Acc) -> Acc;
atomize([{K,V}|Rest], Acc) -> atomize(Rest, [{misc_utils:to_atom(K), V}|Acc]).
