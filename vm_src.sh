function __vm__assert_positional_exists() {
    local name="$1"
    local value="$2"

    [[ -z "$value" ]] && echo "Expect positional arg \"$name\"" && return 1
    return 0
}

function __vm__user_accepted() {
    local message="$1"

    [[ -z "$message" ]] && message="Вы уверены, что хотите выполнить действие?"

    read -p "$message (yes / no): " answer

    [[ "$answer" == "yes" ]] && return 0
    return 1
}

function __vm__dir_exists() {
    __vm__assert_positional_exists dir "$1" || return 1

    [[ -d "$1" ]] && return 0
    return 1
}

function __vm__file_exists() {
    __vm__assert_positional_exists file "$1" || return 1

    [[ -f "$1" ]] && return 0
    return 1
}

function __vm__home() {
    local home="$HOME/.vm/candidates"

    __vm__dir_exists "$home" || mkdir -p "$home"

    echo "$home"
    return 0
}

function __vm__has_app_marker() {
    local app="$1"

    __vm__assert_positional_exists app "$app" || return 1
    __vm__file_exists "$(__vm__get_app_path "$app")/.isapp" || return 1

    return 0
}

function __vm__add_app_marker() {
    local app="$1"
    local path="$(__vm__get_app_path "$app")"

    __vm__assert_positional_exists app "$app" || return 1
    __vm__dir_exists "$path" || return 1
    
    echo '' > "$path/.isapp" && \
    return 0
}

function __vm__has_app() {
    local app="$1"    

    __vm__has_app_marker "$app" && return 0
    return 1
}

function __vm__assert_app_exist() {
    local app="$1"

    __vm__has_app "$app" && return 0
    echo "App "$app" not exist" && return 1
}

function __vm__assert_app_not_exist() {
    local app="$1"

    __vm__has_app "$app" && echo "App "$app" already exists" && return 1
    return 0
}

function __vm__has_version() {
    local app="$1"
    local version="$2"

    __vm__has_app "$app" || return 1
    __vm__assert_positional_exists version "$version" || return 1
    
    __vm__dir_exists "$(__vm__get_app_path "$app")/$version" && return 0

    return 1
}

function __vm__assert_version_exists() {
    local app="$1"
    local version="$2"

    __vm__has_version "$app" "$version" && return 0
    echo "Version "$version" not exists" && return 1   
}

function __vm__assert_version_not_exists() {
    local app="$1"
    local version="$2"

    __vm__has_version "$app" "$version" && echo "Version "$version" already exists" && return 1
    return 0
}

function __vm__get_app_path() {
    local app="$1"
    
    echo "$(__vm__home)/$app"
}

function __vm__apps_list() {
    ls -1 "$(__vm__home)"
}

function __vm__app_list() {
    local app="$1"

    __vm__assert_app_exist "$app" || return 1

    local path="$(__vm__get_app_path "$app")" && \
    ls -1 "$path" | grep -v 'current' && \
    return 0
}

function __vm__add_version() {
    local app="$1"
    local existing_version="$2"
    local version_alias="$3"

    __vm__assert_app_exist "$app" || return 1
    __vm__assert_positional_exists existing_version "$existing_version" || return 1
    __vm__assert_positional_exists version_alias "$version_alias" || return 1

    existing_version="$(realpath "$existing_version")"
    
    local app_path="$(__vm__get_app_path "$app")"

    __vm__dir_exists "$existing_version" || echo "Directory $existing_version doesn't not exists"
    __vm__dir_exists "$existing_version" || return 1

    ln -s "$existing_version" "$app_path/$version_alias" && \
    return 0

    return 1
}

function __vm__create_app() {
    local app="$1"
    local existing_version="$2"
    local version_alias="$3"

    __vm__assert_app_not_exist "$app" || return 1

    local path="$(__vm__get_app_path "$app")"

    mkdir -p "$path" && __vm__add_app_marker "$app"

    [[ -z "$existing_version" ]] && return 0

    __vm__add_version "$app" "$existing_version" "$version_alias" && \
    return 0
}

function __vm__read_version() {
    local app="$1"
    local vers

    local path="$(__vm__get_app_path "$app")/.current"

    __vm__file_exists "$path" || echo ""
    __vm__file_exists "$path" || return 0
    
    local vers=($(cat "$path"))
    vers="${vers[0]}"

    __vm__has_version "$app" "$vers" || echo ""
    __vm__has_version "$app" "$vers" || __vm__write_version "$app" "" --rm
    __vm__has_version "$app" "$vers" || return 0

    echo "$vers"
    return 0
}

function __vm__write_version() {
    local app="$1"
    local version="$2"
    local is_rm="--rm"

    if [[ "$is_rm" != '--rm' ]]; then
        __vm__assert_version_exists "$app" "$version" || return 1
    fi    

    local path="$(__vm__get_app_path "$app")"
    echo "$version" > "$path/.current"    
    return 0
}

function __vm__set() {
    local app="$1"
    local version="$2"
    
    __vm__assert_version_exists "$app" "$version" || return 1

    local path="$(__vm__get_app_path "$app")"

    rm -rf "$path/current" && \
    ln -s "$path/$version" "$path/current" && __vm__write_version "$app" "$version" && \
    __vm__replace_in_path "$path/$(__vm__current_version "$app")" "$path/current"

    return 0
}

function __vm__find_in_path_raw() {
    local pattern="$1"

    __vm__assert_positional_exists pattern "$pattern" || return 1

    local path=(${PATH//:/$'\n'})

    local item
    for item in ${path[@]}; do
        if [[ "$item" =~ $pattern ]]; then
            echo "$item"
        fi
    done
    return 0
}

function __vm__find_in_path() {
    local app="$1"
    local flag="$2"
    
    local pattern="($(__vm__get_app_path "$app"))"

    [[ "$flag" == "--without-base" ]] && \
    __vm__find_in_path_raw "$pattern" | uniq | sed -e "s|$(__vm__get_app_path "$app")/||g" && \
    return 0

    __vm__find_in_path_raw "$pattern" | uniq && return 0
}

function __vm__extract_version_of_path() {
    local version_str=(${1//\//$'\n'})
    echo "${version_str[0]}"
}

function __vm__replace_in_path() {
  local substring="$1"
  local replace_to="$2"

  local src_file="$HOME/.${RANDOM}.sh"

  echo "export PATH=\"$(echo "$PATH" | sed "s|"$substring"|"$replace_to"|g")\"" > "$src_file"

  source "$src_file"
  rm -rf "$src_file"

  return 0
}

function __vm__current_version() {
    local app="$1"

    __vm__assert_app_exist "$app" || return 1
    
    local app_path="$(__vm__get_app_path "$app")"

    local version="$(__vm__find_in_path "$app" --without-base | head -n1)"
    version="$(__vm__extract_version_of_path "$version")"

    ([[ "$version" == "current" ]] || [[ -z "$version" ]]) && __vm__read_version "$app" && return 0

    __vm__has_version "$app" "$version" && \
    echo "$version" && \
    return 0

    echo ""
    return 0
}

function __vm__use() {
    local app="$1"
    local version="$2"

    __vm__assert_app_exist "$app" || return 1
    __vm__assert_version_exists "$app" "$version" || return 1

    local path="$(__vm__get_app_path "$app")"

    __vm__replace_in_path "$path/current" "$path/$version" && \
    __vm__replace_in_path "$path/$(__vm__current_version "$app")" "$path/$version"
    
    return 0
}

function __vm__list() {
    local app="$1"

    [[ -z "$app" ]] && __vm__apps_list && return 0

    __vm__assert_app_exist "$app" || return 1
    local current="$(__vm__current_version "$app")"

    [[ -z "$current" ]] && __vm__app_list "$app" && return 0
    
    __vm__app_list "$app" | sed -e "s|$current|-> $current|g" && return 0

    return 1
}

function __vm__remove_app() {
    local app="$1"

    __vm__user_accepted "Вы уверены, что хотите удалить \"$app\"?" || return 0
    
    local path="$(__vm__get_app_path "$app")"
    rm -r "$path" && \
    return 0
}

function __vm__remove_app_version() {
    local app="$1"
    local version="$2"

    __vm__user_accepted "Вы уверены, что хотите удалить \"$app\" версии \"$version\"?" || return 0

    local path="$(__vm__get_app_path "$app")/$version"
    
    if [[ "$(__vm__read_version "$app")" == "$version" ]]; then
        __vm__write_version "$app" "" --rm && rm -rf "$(__vm__get_app_path "$app")/current"
    fi

    rm -r "$path" && \
    return 0
}

function __vm__remove() {
    local app="$1"
    local version="$2"

    __vm__assert_app_exist "$app" || return 1
    
    [[ -z "$version" ]] && __vm__remove_app "$app" && return 0

    __vm__assert_version_exists "$app" "$version" || return 1

    __vm__remove_app_version "$app" "$version" && return 0
}

function __vm__choised() {
    local app="$1"
    local current="$(__vm__current_version "$app")"

    __vm__assert_app_exist "$app" || return 1

    [[ -z "$current" ]] && echo "No such choised version of \"$app\"" && return 1
    
    echo "$(__vm__get_app_path "$app")/$current"
}

function __vm__path() {
    local app="$1"
    
    __vm__assert_app_exist "$app" || return 1

    local path="$(__vm__get_app_path "$app")"

    echo "$path/current"
    return 0
}

function __vm__command_ls() {
    echo "set"
    echo "use"
    echo "ls"
    echo "version"
    echo "init"
    echo "add"
    echo "rm"
    echo "choised"
    echo "path"
}

function __vm__help() {
    echo 'set <app> <version>'
    echo 'use <app> <version>'
    echo 'version <app>'
    echo 'init <new_app_name> [<path/to/current/version> <new_version_name>]'
    echo 'add <app> <path/to/current/version> <new_version_name>'
    echo 'rm <app> [<version>]'
    echo 'choised <app>'
    echo 'path <app>'
    echo 'ls [<app>]'
}

function vm() {
    case "$1" in
        set) __vm__set "${@:2}" ;;
        use) __vm__use "${@:2}" ;;
        choised) __vm__choised "${@:2}" ;;
        path) __vm__path "${@:2}" ;;
        version) __vm__current_version "${@:2}" ;;
        init) __vm__create_app "${@:2}" ;;
        add) __vm__add_version "${@:2}" ;;
        ls) __vm__list "${@:2}" ;;
        rm) __vm__remove "${@:2}" ;;
        -h) __vm__help ;;
        --help) __vm__help ;;
        *) __vm__help && return 1 ;;
    esac    
}

function __vm__isarg() {
    local pos="$1"

    [[ "$(($COMP_CWORD - 1))" == "$pos" ]] && return 0
    return 1
}

function __vm__dir_complete() {
    compgen -o nospace -f -- "$1"
}

function __vm__words_completation() {
    local latest="${COMP_WORDS[$COMP_CWORD]}"
    local words="$1"
    COMPREPLY=($(compgen -W "$words" -- $latest))
}

function __vm__completation() {
    local prev="${COMP_WORDS[$COMP_CWORD - 1]}"
    local latest="${COMP_WORDS[$COMP_CWORD]}"
    local subcommand="${COMP_WORDS[1]}"

    if __vm__isarg 0; then
        __vm__words_completation "$(__vm__command_ls)"
        return 0        
    fi

    if __vm__isarg 1 && [[ "$subcommand" =~ (set)|(use)|(version)|(add)|(ls)|(rm)|(choised)|(path) ]]; then
        __vm__words_completation "$(__vm__apps_list)"
        return 0        
    fi

    if __vm__isarg 2 && [[ "$subcommand" =~ (set)|(use)|(rm) ]]; then
        __vm__words_completation "$(__vm__app_list "$prev")"
        return 0
    fi

    if __vm__isarg 2 && [[ "$subcommand" =~ (add)|(init) ]]; then
        COMPREPLY=()
        return 0
    fi

    COMPREPLY=("")
    return 0
}

complete -o default -F __vm__completation vm
