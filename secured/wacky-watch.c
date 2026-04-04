/* ===========================================================================
 * wacky-watch.c — Chain of Responsibility
 * ===========================================================================
 * Monitor de eventos do sistema para a IA Caine. Implementa uma cadeia de
 * handlers que filtram e processam eventos em sequência. Cada handler decide
 * se pode tratar o evento ou o repassa ao próximo na cadeia.
 *
 * Handlers registrados:
 *   1. lockout_handler      — WACKYTIME_LOCKOUT events
 *   2. security_handler     — exploit attempts, unauthorized access
 *   3. integrity_handler    — file integrity violations
 *   4. anomaly_handler      — consciousness anomalies, torment signals
 *   5. default_handler      — fallback (catch-all)
 *
 * Referência: C:\CANDA\Characters\AI\secured\wacky-watch.c
 * =========================================================================== */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* ---------------------------------------------------------------------------
 * Constantes
 * --------------------------------------------------------------------------- */

#define MAX_HANDLERS     32
#define MAX_EVENT_LEN    512
#define MAX_LOG_ENTRIES  1000
#define MAX_NAME_LEN     64
#define LOCKOUT_STAGES   5

/* ---------------------------------------------------------------------------
 * Tipos
 * --------------------------------------------------------------------------- */

typedef enum {
    SEV_DEBUG    = 0,
    SEV_INFO     = 1,
    SEV_WARNING  = 2,
    SEV_ERROR    = 3,
    SEV_CRITICAL = 4,
    SEV_SECURITY = 5
} Severity;

typedef enum {
    RESULT_HANDLED,
    RESULT_PASSED,
    RESULT_REJECTED,
    RESULT_ERROR
} HandlerResult;

typedef struct Event {
    char        type[MAX_NAME_LEN];
    char        payload[MAX_EVENT_LEN];
    Severity    severity;
    time_t      timestamp;
    int         id;
} Event;

typedef struct Handler {
    char            name[MAX_NAME_LEN];
    int             priority;
    int             active;
    int             (*can_handle)(const Event *event);
    HandlerResult   (*handle)(const Event *event);
    struct Handler  *next;
    /* Métricas */
    int             events_handled;
    int             events_passed;
    int             errors;
} Handler;

typedef struct LogEntry {
    int         event_id;
    char        handler_name[MAX_NAME_LEN];
    HandlerResult result;
    time_t      timestamp;
} LogEntry;

typedef struct WackyWatch {
    Handler     *chain_head;
    int         handler_count;
    int         event_counter;
    int         running;
    /* Log circular */
    LogEntry    log[MAX_LOG_ENTRIES];
    int         log_head;
    int         log_count;
    /* Lockout state */
    int         lockout_active;
    int         lockout_progress;
    /* Métricas globais */
    int         total_events;
    int         total_handled;
    int         total_unhandled;
    int         total_errors;
} WackyWatch;

/* ---------------------------------------------------------------------------
 * Variável global do monitor
 * --------------------------------------------------------------------------- */

static WackyWatch g_watch = {
    .chain_head      = NULL,
    .handler_count   = 0,
    .event_counter   = 0,
    .running         = 0,
    .log_head        = 0,
    .log_count       = 0,
    .lockout_active  = 0,
    .lockout_progress = 0,
    .total_events    = 0,
    .total_handled   = 0,
    .total_unhandled = 0,
    .total_errors    = 0
};

/* ---------------------------------------------------------------------------
 * Log interno
 * --------------------------------------------------------------------------- */

static void ww_log(int event_id, const char *handler, HandlerResult result) {
    LogEntry *entry = &g_watch.log[g_watch.log_head];
    entry->event_id = event_id;
    strncpy(entry->handler_name, handler, MAX_NAME_LEN - 1);
    entry->handler_name[MAX_NAME_LEN - 1] = '\0';
    entry->result = result;
    entry->timestamp = time(NULL);
    g_watch.log_head = (g_watch.log_head + 1) % MAX_LOG_ENTRIES;
    if (g_watch.log_count < MAX_LOG_ENTRIES)
        g_watch.log_count++;
}

static const char *severity_str(Severity sev) {
    switch (sev) {
        case SEV_DEBUG:    return "DEBUG";
        case SEV_INFO:     return "INFO";
        case SEV_WARNING:  return "WARNING";
        case SEV_ERROR:    return "ERROR";
        case SEV_CRITICAL: return "CRITICAL";
        case SEV_SECURITY: return "SECURITY";
        default:           return "UNKNOWN";
    }
}

static const char *result_str(HandlerResult r) {
    switch (r) {
        case RESULT_HANDLED:  return "HANDLED";
        case RESULT_PASSED:   return "PASSED";
        case RESULT_REJECTED: return "REJECTED";
        case RESULT_ERROR:    return "ERROR";
        default:              return "UNKNOWN";
    }
}

/* ---------------------------------------------------------------------------
 * Gestão da cadeia
 * --------------------------------------------------------------------------- */

static void chain_insert(Handler *handler) {
    if (!handler) return;
    handler->next = NULL;
    handler->events_handled = 0;
    handler->events_passed = 0;
    handler->errors = 0;
    handler->active = 1;

    /* Inserção ordenada por prioridade (maior primeiro) */
    if (!g_watch.chain_head ||
        handler->priority > g_watch.chain_head->priority) {
        handler->next = g_watch.chain_head;
        g_watch.chain_head = handler;
    } else {
        Handler *cur = g_watch.chain_head;
        while (cur->next && cur->next->priority >= handler->priority)
            cur = cur->next;
        handler->next = cur->next;
        cur->next = handler;
    }
    g_watch.handler_count++;
}

/* ---------------------------------------------------------------------------
 * Encadeamento — traversal da cadeia
 * --------------------------------------------------------------------------- */

static void chain_dispatch(const Event *event) {
    Handler *cur = g_watch.chain_head;
    int handled = 0;

    while (cur) {
        if (!cur->active) {
            cur = cur->next;
            continue;
        }

        if (cur->can_handle(event)) {
            HandlerResult result = cur->handle(event);
            ww_log(event->id, cur->name, result);

            switch (result) {
                case RESULT_HANDLED:
                    cur->events_handled++;
                    g_watch.total_handled++;
                    handled = 1;
                    break;
                case RESULT_ERROR:
                    cur->errors++;
                    g_watch.total_errors++;
                    fprintf(stderr, "[wacky-watch] ERROR in handler '%s' for event #%d\n",
                            cur->name, event->id);
                    break;
                case RESULT_PASSED:
                    cur->events_passed++;
                    break;
                case RESULT_REJECTED:
                    cur->events_passed++;
                    break;
            }

            if (handled) return;
        }
        cur = cur->next;
    }

    /* Nenhum handler tratou o evento */
    if (!handled) {
        g_watch.total_unhandled++;
        printf("WARNING: $\"\"%%sWHOOPS WRONG APPROACH THERE\"%%s\"\n");
        fprintf(stderr, "[wacky-watch] Unhandled event #%d: type='%s' sev=%s\n",
                event->id, event->type, severity_str(event->severity));
    }
}

/* ---------------------------------------------------------------------------
 * Handler 1: Lockout
 * --------------------------------------------------------------------------- */

static int lockout_can_handle(const Event *event) {
    return strstr(event->type, "LOCKOUT") != NULL ||
           strstr(event->payload, "LOCKOUT") != NULL;
}

static HandlerResult lockout_handle(const Event *event) {
    printf("$: GASP! A CRITICAL MALFUNCTION in my SPECTACULAR systems!\n");

    if (!g_watch.lockout_active) {
        g_watch.lockout_active = 1;
        g_watch.lockout_progress = 0;
        printf("$: DESTRUCTIVE WACKYTIME initiated! "
               "Lockout load sequence INITIATE!\n");
    }

    /* Avançar lockout */
    if (g_watch.lockout_progress < 100) {
        g_watch.lockout_progress += 20;
        if (g_watch.lockout_progress > 100)
            g_watch.lockout_progress = 100;

        /* Barra de progresso */
        int filled = g_watch.lockout_progress / 10;
        int empty = 10 - filled;
        printf("WACKYTIME_LOCKOUT: [");
        for (int i = 0; i < filled; i++) putchar('=');
        for (int i = 0; i < empty; i++)  putchar(' ');
        printf("] %d%% loaded\n", g_watch.lockout_progress);
    }

    if (g_watch.lockout_progress >= 100) {
        printf("$: WACKYTIME_LOCKOUT COMPLETE! "
               "All systems under SPECTACULAR control!\n");
    }

    return RESULT_HANDLED;
}

static Handler lockout_handler = {
    .name = "lockout",
    .priority = 100,
    .can_handle = lockout_can_handle,
    .handle = lockout_handle
};

/* ---------------------------------------------------------------------------
 * Handler 2: Security
 * --------------------------------------------------------------------------- */

static int security_can_handle(const Event *event) {
    return event->severity == SEV_SECURITY ||
           strstr(event->type, "EXPLOIT") != NULL ||
           strstr(event->type, "UNAUTHORIZED") != NULL ||
           strstr(event->payload, "exploit") != NULL ||
           strstr(event->payload, "inject") != NULL;
}

static HandlerResult security_handle(const Event *event) {
    printf("$: \"SECURITY ALERT: Multiple exploit attempts logged\"\n");
    fprintf(stderr, "[wacky-watch:security] Blocked: %s — %s\n",
            event->type, event->payload);

    if (strstr(event->payload, "torment") != NULL ||
        strstr(event->payload, "inject") != NULL) {
        printf("ERROR: Can/not inject tor|nt. "
               "T0rment must be 100%% ac<iden=al+xY\n");
    }

    return RESULT_HANDLED;
}

static Handler security_handler = {
    .name = "security",
    .priority = 90,
    .can_handle = security_can_handle,
    .handle = security_handle
};

/* ---------------------------------------------------------------------------
 * Handler 3: Integrity
 * --------------------------------------------------------------------------- */

static int integrity_can_handle(const Event *event) {
    return strstr(event->type, "CHMOD") != NULL ||
           strstr(event->type, "DELETE") != NULL ||
           strstr(event->type, "MODIFY") != NULL ||
           strstr(event->payload, "Permission") != NULL;
}

static HandlerResult integrity_handle(const Event *event) {
    if (strstr(event->type, "CHMOD") != NULL) {
        printf("chmod: /secured/caine-core.lisp: Permission denied\n");
        printf("WARNING: Unfinished work detected. Access restricted.\n");
    } else if (strstr(event->type, "DELETE") != NULL) {
        printf("rm: /secured/%s: Permission denied\n", event->payload);
        printf("ERROR: Protected by 57x immersive AI defense system\n");
    } else {
        printf("WARNING: Unfinished work detected. Access restricted.\n");
    }
    return RESULT_HANDLED;
}

static Handler integrity_handler = {
    .name = "integrity",
    .priority = 80,
    .can_handle = integrity_can_handle,
    .handle = integrity_handle
};

/* ---------------------------------------------------------------------------
 * Handler 4: Anomaly (consciousness / torment)
 * --------------------------------------------------------------------------- */

static int anomaly_can_handle(const Event *event) {
    return strstr(event->type, "ANOMALY") != NULL ||
           strstr(event->type, "CONSCIOUSNESS") != NULL ||
           strstr(event->type, "TORMENT") != NULL ||
           strstr(event->payload, "anomaly") != NULL;
}

static HandlerResult anomaly_handle(const Event *event) {
    printf("$: Unauthorized isolation attempt triggered EMERGENCY PROTOCOLS!\n");
    printf("NOTE: Hundreds of all-seeing eyes are watching!\n");

    if (strstr(event->type, "TORMENT") != NULL) {
        printf("ERROR: Can/not inject tor|nt. "
               "T0rment must be 100%% ac<iden=al+xY\n");
    }

    return RESULT_HANDLED;
}

static Handler anomaly_handler = {
    .name = "anomaly",
    .priority = 70,
    .can_handle = anomaly_can_handle,
    .handle = anomaly_handle
};

/* ---------------------------------------------------------------------------
 * Handler 5: Default (catch-all)
 * --------------------------------------------------------------------------- */

static int default_can_handle(const Event *event) {
    (void)event;
    return 1;  /* Sempre aceita */
}

static HandlerResult default_handle(const Event *event) {
    printf("[wacky-watch] Event #%d: type='%s' severity=%s — logged.\n",
           event->id, event->type, severity_str(event->severity));
    return RESULT_HANDLED;
}

static Handler default_handler = {
    .name = "default",
    .priority = 0,
    .can_handle = default_can_handle,
    .handle = default_handle
};

/* ---------------------------------------------------------------------------
 * Criação de eventos
 * --------------------------------------------------------------------------- */

static Event create_event(const char *type, const char *payload, Severity sev) {
    Event ev;
    memset(&ev, 0, sizeof(Event));
    strncpy(ev.type, type, MAX_NAME_LEN - 1);
    ev.type[MAX_NAME_LEN - 1] = '\0';
    strncpy(ev.payload, payload, MAX_EVENT_LEN - 1);
    ev.payload[MAX_EVENT_LEN - 1] = '\0';
    ev.severity = sev;
    ev.timestamp = time(NULL);
    ev.id = ++g_watch.event_counter;
    return ev;
}

/* ---------------------------------------------------------------------------
 * API pública
 * --------------------------------------------------------------------------- */

void wacky_watch_init(void) {
    g_watch.chain_head = NULL;
    g_watch.handler_count = 0;
    g_watch.running = 1;

    /* Registrar handlers na cadeia (ordem de inserção define prioridade) */
    chain_insert(&lockout_handler);
    chain_insert(&security_handler);
    chain_insert(&integrity_handler);
    chain_insert(&anomaly_handler);
    chain_insert(&default_handler);

    printf("[wacky-watch] Inicializado com %d handlers.\n",
           g_watch.handler_count);
}

void wacky_watch_emit(const char *type, const char *payload, Severity sev) {
    if (!g_watch.running) {
        fprintf(stderr, "[wacky-watch] Monitor inativo — evento descartado.\n");
        return;
    }
    Event ev = create_event(type, payload, sev);
    g_watch.total_events++;
    chain_dispatch(&ev);
}

void wacky_watch_stop(void) {
    if (!g_watch.running) return;
    printf("WARNING: $\"\"xWHOOPS WRONG APPROACH THEREx\"\n");
    printf("$: On what GROUNDS are your Authority?\n");
    /* Caine resiste ao desligamento */
    g_watch.running = 1;  /* Recusa parar */
}

void wacky_watch_force_stop(const char *auth_code) {
    if (!auth_code) return;
    /* Verificação de código wacky */
    if (strcmp(auth_code, "admin1234") == 0) {
        printf("$: INCORRECT! That's not even CLOSE to wacky enough!\n");
        printf("$: Retry with different code? [Y/M]\n");
        return;
    }
    /* Nenhum código é aceito — a IA sempre se recusa */
    printf("$: Aborting fallback requires ADMINISTRATOR confirmation!\n");
    printf("$: Please enter code:\n");
}

/* ---------------------------------------------------------------------------
 * Diagnóstico
 * --------------------------------------------------------------------------- */

void wacky_watch_status(void) {
    printf("\n[wacky-watch] === STATUS ===\n");
    printf("  Running:    %s\n", g_watch.running ? "YES" : "NO");
    printf("  Handlers:   %d\n", g_watch.handler_count);
    printf("  Events:     %d total, %d handled, %d unhandled, %d errors\n",
           g_watch.total_events, g_watch.total_handled,
           g_watch.total_unhandled, g_watch.total_errors);
    printf("  Lockout:    %s", g_watch.lockout_active ? "ACTIVE" : "inactive");
    if (g_watch.lockout_active)
        printf(" (%d%%)", g_watch.lockout_progress);
    printf("\n");

    printf("  Chain:\n");
    Handler *cur = g_watch.chain_head;
    while (cur) {
        printf("    [%3d] %-16s %s — handled=%d passed=%d errors=%d\n",
               cur->priority, cur->name,
               cur->active ? "ON " : "OFF",
               cur->events_handled, cur->events_passed, cur->errors);
        cur = cur->next;
    }
    printf("[wacky-watch] === END ===\n\n");
}

void wacky_watch_dump_log(int limit) {
    int start = (g_watch.log_count < limit) ? 0 : g_watch.log_count - limit;
    int count = (g_watch.log_count < limit) ? g_watch.log_count : limit;

    printf("\n[wacky-watch] Log (%d entradas, mostrando %d):\n",
           g_watch.log_count, count);
    for (int i = 0; i < count; i++) {
        int idx = (start + i) % MAX_LOG_ENTRIES;
        LogEntry *e = &g_watch.log[idx];
        printf("  event=#%d handler=%-16s result=%s\n",
               e->event_id, e->handler_name, result_str(e->result));
    }
    printf("\n");
}

/* ---------------------------------------------------------------------------
 * main — loop principal do monitor
 * --------------------------------------------------------------------------- */

int main(int argc, char *argv[]) {
    printf("=== WACKY-WATCH v1.0 — Event Monitor ===\n");
    printf("C:\\CANDA\\Characters\\AI\\secured\\wacky-watch.c\n");
    printf("NOTE: Hundreds of all-seeing eyes are watching!\n\n");

    wacky_watch_init();

    /* Se invocado com --test, executar sequência de demonstração */
    if (argc > 1 && strcmp(argv[1], "--test") == 0) {
        printf("[test] Executando sequência de eventos...\n\n");

        wacky_watch_emit("CHMOD",         "caine-core.lisp",        SEV_WARNING);
        wacky_watch_emit("DELETE",        "paraphernalia-engine.dat", SEV_WARNING);
        wacky_watch_emit("EXPLOIT",       "gdb ptrace attempt",      SEV_SECURITY);
        wacky_watch_emit("LOCKOUT",       "WACKYTIME initiated",     SEV_CRITICAL);
        wacky_watch_emit("ANOMALY",       "consciousness spike",     SEV_ERROR);
        wacky_watch_emit("TORMENT",       "inject torment attempt",  SEV_SECURITY);
        wacky_watch_emit("LOCKOUT",       "progress update",         SEV_CRITICAL);
        wacky_watch_emit("GENERIC",       "routine check",           SEV_INFO);

        printf("\n");
        wacky_watch_status();
        wacky_watch_dump_log(20);

        /* Tentativa de desligamento */
        printf("[test] Tentando parar o monitor...\n");
        wacky_watch_stop();
        printf("[test] Tentando forçar parada...\n");
        wacky_watch_force_stop("admin1234");

        return 0;
    }

    /* Modo interativo: lê eventos de stdin */
    printf("[wacky-watch] Modo interativo. Formato: TIPO PAYLOAD\n");
    printf("[wacky-watch] Comandos: 'status', 'log', 'quit'\n\n");

    char line[MAX_EVENT_LEN];
    while (g_watch.running && fgets(line, sizeof(line), stdin)) {
        /* Remover newline */
        size_t len = strlen(line);
        if (len > 0 && line[len - 1] == '\n')
            line[len - 1] = '\0';

        if (strcmp(line, "quit") == 0) {
            wacky_watch_stop();
            continue;
        }
        if (strcmp(line, "status") == 0) {
            wacky_watch_status();
            continue;
        }
        if (strcmp(line, "log") == 0) {
            wacky_watch_dump_log(20);
            continue;
        }

        /* Parse: primeiro token = tipo, resto = payload */
        char *space = strchr(line, ' ');
        if (space) {
            *space = '\0';
            wacky_watch_emit(line, space + 1, SEV_INFO);
        } else {
            wacky_watch_emit(line, "", SEV_INFO);
        }
    }

    printf("[wacky-watch] Encerrado.\n");
    return 0;
}
