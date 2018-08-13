type param =
    {
    typ: string;
    opt: bool;
    name: string;
    of_string: string;
    to_string: string;
    }

let ocaml_of_mysql = function
    | "INT"  -> Ok ("int64", "Int64.of_string", "Int64.to_string")
    | "TEXT" -> Ok ("string", "Ppx_mysql_lib.identity", "Ppx_mysql_lib.identity")
    | _      -> Error ()

let identity x = x

let map_option f = function
    | Some x -> Some (f x)
    | None   -> None

let parse_query =
    let param_re = Re.(seq [
        group (rep1 (compl [char '{'; char '?']));
        group (opt (char '?'));
        char '{';
        group (rep1 (compl [char '}']));
        char '}';
        ]) |> Re.compile in
    fun query ->
        let len = String.length query in
        let buf = Buffer.create len in
        let rec main_loop i string_delim acc_in acc_out =
            if i >= len
            then match string_delim with
                | None   -> Ok (Buffer.contents buf, List.rev acc_in, List.rev acc_out)
                | Some _ -> Error `Unterminated_string
            else
                let this = query.[i] in
                match string_delim with
                    | _ when this = '\\' ->
                        Buffer.add_char buf this;
                        if i + 1 >= len
                        then
                            Error `Escape_at_end
                        else begin
                            Buffer.add_char buf query.[i + 1];
                            main_loop (i + 2) string_delim acc_in acc_out
                        end
                    | None when this = '\'' || this = '"' ->
                        Buffer.add_char buf this;
                        main_loop (i + 1) (Some this) acc_in acc_out
                    | None when this = '%' ->
                        parse_param (i + 1) `In_param acc_in acc_out
                    | None when this = '@' ->
                        parse_param (i + 1) `Out_param acc_in acc_out
                    | Some delim when this = delim ->
                        Buffer.add_char buf this;
                        if i + 1 < len && query.[i + 1] = delim
                        then begin
                            Buffer.add_char buf this;
                            main_loop (i + 2) string_delim acc_in acc_out
                        end
                        else begin
                            main_loop (i + 1) None acc_in acc_out
                        end
                    | _ ->
                        Buffer.add_char buf this;
                        main_loop (i + 1) string_delim acc_in acc_out
        and parse_param i param_typ acc_in acc_out =
            match Re.exec_opt ~pos:i param_re query with
                | None ->
                    Error `Bad_param
                | Some groups ->
                    begin match Re.Group.all groups with
                        | [| all; typ; opt; name |] ->
                            begin match ocaml_of_mysql typ with
                                | Ok (typ, of_string, to_string) ->
                                    let param = {typ; opt = opt = "?"; name; of_string; to_string} in
                                    let (replacement, acc_in, acc_out) = match param_typ with
                                        | `In_param  -> ("?", param :: acc_in, acc_out)
                                        | `Out_param -> (name, acc_in, param :: acc_out) in
                                    Buffer.add_string buf replacement;
                                    main_loop (i + String.length all) None acc_in acc_out
                                | Error () ->
                                    Error (`Unknown_mysql_type typ)
                            end
                        | _ ->
                            assert false (* This should never happen. *)
                    end
        in main_loop 0 None [] []

(*
let perform ?(min = 0) ?max dbh expr =
    Mysql.Prepared.execute_null expr.statement expr.params >>= fun stmt_result ->
    let rec loop acc acc_len =
        MySql.Prepared.fetch stmt_result >>= function
            | Some arr when acc_len < max ->
                begin match expr.parse_result arr with
                    | Some parsed -> loop (parsed :: acc) (acc_len + 1)
                    | None -> return (Error `Unexpected_output)
                end
            | Some arr ->
                return (Error `Too_many_results)
            | None when acc_len >= min ->
                return (Ok acc)
            | None ->
                return (Error `Too_few_results)
    in loop [] 0

let select_one dbh expr =
    perform ~min:1 ~max:1 dbh expr >>>| function
        | [x] -> x
        | _   -> assert false

let select_opt dbh expr =
    perform ~max:1 dbh expr >>>| function
        | [x] -> Some x
        | []  -> None
        | _   -> assert false

let select_all dbh expr =
    perform dbh expr

let execute dbh expr =
    perform ~max:0 dbh expr >>>| function
        | [] -> ()
        | _  -> assert false
*)

