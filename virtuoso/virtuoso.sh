#!/bin/sh

### Parameters

port=${VIRTUOSO_PORT:-1111}
user=${VIRTUOSO_USER:-dba}
pass=${VIRTUOSO_PASS:-dba}

## Options for the source code distribution

# To use the Virtuoso source code distribution, change the following default environmental variables when needed.
#
# * VIRTUOSO_PREFIX="/opt/virtuoso"
# * VIRTUOSO_DBDIR="${VIRTUOSO_PREFIX}/var/lib/virtuoso/db"
# * VIRTUOSO_DBFILE="virtuoso"

## Options for binary packages

# Downloaded from (as of release v7.2.5.1)
#   * https://github.com/openlink/virtuoso-opensource/releases
# Linux
#   * virtuoso-opensource.x86_64-generic_glibc25-linux-gnu.tar.gz
# Mac OS X (macOS)
#   * virtuoso-opensource-7.2.5-macosx-app.dmg
# Windows
#   * Virtuoso_OpenSource_Server_7.20.x64.exe
#
# To use the Virtuoso Linux binary package, set the following environmental variables.
#
# * VIRTUOSO_PREFIX="/opt/virtuoso-opensource"
# * VIRTUOSO_DBDIR="${VIRTUOSO_PREFIX}/database"
# * VIRTUOSO_DBFILE="virtuoso"
#
# To use the Virtuoso OS X binary package, set the following environmental variables.
#
# * VIRTUOSO_PREFIX="/Applications/Virtuoso Open Source Edition v7.2.app/Contents/virtuoso-opensource"
# * VIRTUOSO_DBDIR="${VIRTUOSO_PREFIX}/database"
# * VIRTUOSO_DBFILE="database"
#
# To use the Virtuoso Windows binary package, set the following environmental variables.
#
# * VIRTUOSO_PREFIX="/mnt/c/Program Files/OpenLink Software/Virtuoso OpenSource 7.20/"
# * VIRTUOSO_DBDIR="${VIRTUOSO_PREFIX}/database"
# * VIRTUOSO_DBFILE="virtuoso"
# * VIRTUOSO_SUFFIX=".exe"

prefix=${VIRTUOSO_PREFIX:-/opt/virtuoso}
dbdir=${VIRTUOSO_DBDIR:-${prefix}/var/lib/virtuoso/db}
dbfile=${VIRTUOSO_DBFILE:-virtuoso}
suffix=${VIRTUOSO_SUFFIX}

isql="${prefix}/bin/isql${suffix}"
opts="${port} ${user} ${pass}"

case $1 in
    start)
        (cd "${dbdir}"; "${prefix}/bin/virtuoso-t${suffix}")
        ;;
    stop)
        echo "shutdown;" | "${isql}" ${opts}
        ;;
    status)
        echo "isql ${port}"
        echo "status();" | "${isql}" ${opts}
        echo
        ;;
    isql)
        "${isql}" ${opts}
        ;;
    port)
        echo "${port}"
        ;;
    path)
        echo "${dbdir}"
        ;;
    dir)
        ls -l "${dbdir}"
        ;;
    log)
        tail -f "${dbdir}/${dbfile}.log"
        ;;
    edit)
        ${EDITOR:-vi} "${dbdir}/virtuoso.ini"
        ;;
    password)
        echo "Changing password for dba."
        read -s -p "New password: " newpass
        echo
        read -s -p "Retype New Password: " newpass2
        echo
        if [ ${newpass:?"Required non empty password"} -a ${newpass} = ${newpass2} ]; then
          echo "set password ${pass} ${newpass};" | "${isql}" ${opts}
          echo
          echo "Don't forget to update:"
          echo "  * the pass variable in this shell script ($0)"
          echo "  * and/or the VIRTUOSO_PASS environmental variable"
        else
          echo "Aborted."
        fi
        ;;
    enable_cors)
        read -p "Enable CORS to all domains (recommended for all SPARQL endpoints). Continue? (Yes/No): " answer
        if [ "${answer:-No}" = "Yes" ]; then
          echo "
            DB.DBA.VHOST_DEFINE (lpath=>'/sparql_1', ppath=>'/!sparql/', opts=>vector('cors','*'));
            UPDATE http_path SET HP_OPTIONS = (SELECT HP_OPTIONS FROM http_path WHERE HP_LPATH='/sparql_1') WHERE HP_LPATH='/sparql';
            DB.DBA.VHOST_REMOVE (lpath=>'/sparql_1');
          " | "${isql}" ${opts}
        else
          echo "Aborted."
        fi
        ;;
    delete)
        read -p "Deleate all data. Continue? (Yes/No): " answer
        if [ "${answer:-No}" = "Yes" ]; then
          mv "${dbdir}/virtuoso.ini" "${prefix}/virtuoso.ini"
          rm -f "${dbdir}"/*
          mv "${prefix}/virtuoso.ini" "${dbdir}/virtuoso.ini"
        else
          echo "Aborted."
        fi
        ;;
    loadrdf)
        echo "
          log_enable(2,1);
          DB.DBA.RDF_LOAD_RDFXML_MT(file_to_string_output('$3'), '', '$2');
          checkpoint;
        " | "${isql}" ${opts}
        ;;
    loadttl)
        echo "
          log_enable(2,1);
          DB.DBA.TTLP_MT(file_to_string_output('$3'), '', '$2', 337);
          checkpoint;
        " | "${isql}" ${opts}
        ;;
    loaddir)
        echo "
          log_enable(2,1);
          ld_dir_all('$3', '$4', '$2');
          rdf_loader_run();
          checkpoint;
        " | "${isql}" ${opts}
        ;;
    addloader)
        echo "rdf_loader_run();" | "${isql}" ${opts} &
        ;;
    watch)
        echo "
          SELECT \
            CASE ll_state \
              WHEN 0 THEN 'Waiting' \
              WHEN 1 THEN 'Loading' \
              WHEN 2 THEN 'Done' \
              ELSE 'Unknown' \
            END AS status, \
            COUNT(*) AS files \
          FROM DB.DBA.LOAD_LIST \
          GROUP BY ll_state \
          ORDER BY status;
        " | "${isql}" ${opts}
        ;;
    watch_wait)
        echo "
          SELECT ll_graph, ll_file \
          FROM DB.DBA.LOAD_LIST \
          WHERE ll_state = 0;
        " | "${isql}" ${opts} | perl -ne 's/  +/\t/g; print if /^(SQL> ll|http)/#'
        ;;
    watch_load)
        echo "
          SELECT ll_graph, ll_file, ll_started \
          FROM DB.DBA.LOAD_LIST \
          WHERE ll_state = 1;
        " | "${isql}" ${opts} | perl -ne 's/  +/\t/g; print if /^(SQL> ll|http)/#'
        ;;
    watch_done)
        echo "
          SELECT ll_graph, ll_file, ll_started, (ll_done - ll_started) AS duration \
          FROM DB.DBA.LOAD_LIST \
          WHERE ll_state = 2;
        " | "${isql}" ${opts} | perl -ne 's/  +/\t/g; print if /^(SQL> ll|http)/#'
        ;;
    watch_error)
        echo "
          SELECT ll_graph, ll_file, ll_started, (ll_done - ll_started) AS duration, ll_error \
          FROM DB.DBA.LOAD_LIST \
          WHERE ll_error IS NOT NULL;
        " | "${isql}" ${opts} | perl -ne 's/  +/\t/g; print if /^(SQL> ll|http)/#'
        ;;
    list)
        echo "SELECT * FROM SPARQL_SELECT_KNOWN_GRAPHS_T ORDER BY GRAPH_IRI;" | "${isql}" ${opts}
        ;;
    head)
        echo "SPARQL SELECT DISTINCT * WHERE { GRAPH <$2> {?s ?p ?o} } LIMIT 10;" | "${isql}" ${opts}
        ;;
    drop)
        read -p "Deleate all data in the graph '$2'. Continue? (Yes/No): " answer
        if [ "${answer:-No}" = "Yes" ]; then
          echo "
            log_enable(2,1);
            SPARQL CLEAR GRAPH <$2>;
            checkpoint;
          " | "${isql}" ${opts}
          echo "SPARQL SELECT COUNT(*) FROM <$2> WHERE {?s ?p ?o};" | "${isql}" ${opts}
          echo "DELETE FROM DB.DBA.LOAD_LIST WHERE ll_graph = '$2';" | "${isql}" ${opts}
        else
          echo "Aborted."
        fi
        ;;
    query)
        echo "SPARQL $2 ;" | "${isql}" ${opts}
        ;;
    help)
        echo "Usage:"
        echo "  Show this help"
        echo "    $0 help"
        echo "  Start the virtuoso server"
        echo "    $0 start"
        echo "  Stop the virtuoso server"
        echo "    $0 stop"
        echo "  Show the status of the server"
        echo "    $0 status"
        echo "  Invoke the isql command"
        echo "    $0 isql"
        echo "  Show a port number of the server"
        echo "    $0 port"
        echo "  Show a path to the data directory"
        echo "    $0 path"
        echo "  Show directory contents of the data directory"
        echo "    $0 dir"
        echo "  Show a log file of the server"
        echo "    $0 log"
        echo "  Edit a config file of the server"
        echo "    $0 edit"
        echo "  Enable 'Access-Control-Allow-Origin: *' to allow Cross-Origin Resource Sharing (CORS) for all domains"
        echo "    $0 enable_cors"
        echo "  Delete entire data (except for a config file)"
        echo "    $0 delete"
        echo
        echo "  Load RDF files"
        echo "    $0 loadrdf 'http://example.org/graph_uri' /path/to/file.rdf"
        echo "    $0 loadttl 'http://example.org/graph_uri' /path/to/file.ttl"
        echo "    $0 loaddir 'http://example.org/graph_uri' /path/to/directory glob_pattern"
        echo "      (where glob_pattern can be something like '*.ttl' or '*.rdf')"
        echo "  Count remaining files to be loaded"
        echo "    $0 watch"
        echo "  List file names to be loaded, being loaded, and finished loading"
        echo "    $0 watch_wait"
        echo "    $0 watch_load"
        echo "    $0 watch_done"
        echo "  List file names with loading errors"
        echo "    $0 watch_error"
        echo "  Add an extra loading process"
        echo "    $0 addloader"
        echo
        echo "  List graphs"
        echo "    $0 list"
        echo "  Peek a graph"
        echo "    $0 head 'http://example.org/graph_uri'"
        echo "  Drop a graph"
        echo "    $0 drop 'http://example.org/graph_uri'"
        echo
        echo "  Execute a SPARQL query via the isql command"
        echo "    $0 query 'select * where {?your ?sparql ?query.} limit 100'"
        echo
        exit 2
        ;;
    *)
        echo "Usage:"
        echo "$0 help"
        echo "$0 {start|stop|status|isql|port|path|dir|log|edit|enable_cors|delete}"
        echo "$0 {loadrdf|loadttl} 'http://example.org/graph_uri' /path/to/file"
        echo "$0 {loaddir} 'http://example.org/graph_uri' /path/to/directory '*.(ttl|rdf|owl)'"
        echo "$0 {addloader|watch|watch_wait|watch_load|watch_done|watch_error}"
        echo "$0 {list|head|drop} [graph_uri]"
        echo "$0 query 'select * where {?your ?sparql ?query.} limit 100'"
        exit 2
esac

