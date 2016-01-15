-module(sql_bridge_epgsql).
-behaviour(sql_bridge_adapter).
-include("compat.hrl").

-export([start/0,
		 connect/5,
		 query/3,
		 query/4,
		 encode/1]).

start() ->
	application:start(poolboy),
	%application:start(epgsql),
	ok.

connect(DB, User, Pass, Host, Port) when is_atom(DB) ->
	WorkerArgs = [
		{database, atom_to_list(DB)},
		{hostname, Host},
		{username, User},
		{password, Pass},
		{port, Port}
	],
	sql_bridge_utils:start_poolboy_pool(DB, WorkerArgs, sql_bridge_epgsql_worker),
	ok.

query(Type, DB, Q) ->
	query(Type, DB, Q, []).

query(Type, DB, Q, ParamList) ->
	try query_catched(Type, DB, Q, ParamList)
	catch
		exit:{noproc, _} ->
			{error, no_pool}
	end.

query_catched(Type, DB, Q, ParamList) ->
	ToRun = fun(Worker) ->
		%% calls sql_bridge_epgsql_worker:handle_call()
		gen_server:call(Worker, {equery, Q, ParamList})
	end,
	Res = sql_bridge_utils:with_poolboy_pool(DB, ToRun),
	{ok, format_result(Type, Res)}.

format_result(UID, {ok, Count}) when UID=:=update;
									 UID=:=insert;
									 UID=:=delete ->
	Count;
format_result(tuple, {ok, _Columns, Rows}) ->
	Rows;
format_result(list, {ok, _Columns, Rows}) ->
	[tuple_to_list(Row) || Row <- Rows];
format_result(proplist, {ok, Columns, Rows}) ->
	format_proplists(Columns, Rows);
format_result(dict, {ok, Columns, Rows}) ->
	format_dicts(Columns, Rows);
format_result(map, {ok, Columns, Rows}) ->
	format_maps(Columns, Rows).

format_proplists(Columns, Rows) ->
	ColNames = extract_colnames(Columns),
	[make_proplist(ColNames, Row) || Row <- Rows].

format_dicts(Columns, Rows) ->
	ColNames = extract_colnames(Columns),
	[make_dict(ColNames, Row) || Row <- Rows].

make_dict(Cols, Row) when is_tuple(Row) ->
	make_dict(Cols, tuple_to_list(Row), dict:new()).

make_dict([], [], Dict) ->
	Dict;
make_dict([Col|Cols], [Val|Vals], Dict) ->
	NewDict = dict:store(Col, Val, Dict),
	make_dict(Cols, Vals, NewDict).

	
extract_colnames(Columns) ->
	[list_to_atom(binary_to_list(CN)) || {column, CN, _, _, _, _} <- Columns].


make_proplist(Columns, Row) when is_tuple(Row) ->
	make_proplist(Columns, tuple_to_list(Row));
make_proplist([Col|Cols], [Val|Vals]) ->
	[{Col, Val} | make_proplist(Cols, Vals)];
make_proplist([], []) ->
	[].

-ifdef(has_maps).
format_maps(Columns, Rows) ->
	ColNames = extract_colnames(Columns),
	[make_map(ColNames, Row) || Row <- Rows].

make_map(Cols, Row) ->
	make_map(Cols, tuple_to_list(Row), maps:new()).

make_map([], [], Map) ->
	Map;
make_map([Col|Cols],[Val|Vals], Map) ->
	NewMap = maps:put(Col, Val, Map),
	make_map(Cols, Vals, NewMap).

-else.
format_maps(_,_) ->
	throw(maps_not_supported).
-endif.

encode(Val) ->
	Val.
