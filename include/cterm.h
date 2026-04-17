#ifndef CTERM_H
#define CTERM_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================
// Configuration
// ============================================================

typedef struct CTermConfig CTermConfig;

CTermConfig* cterm_config_create(void);
void cterm_config_destroy(CTermConfig* config);
bool cterm_config_load(CTermConfig* config, const char* path);
bool cterm_config_save(const CTermConfig* config, const char* path);
const char* cterm_config_get(const CTermConfig* config, const char* key);
void cterm_config_set(CTermConfig* config, const char* key, const char* value);

// ============================================================
// Layout Management
// ============================================================

typedef struct {
    double x;
    double y;
    double width;
    double height;
} CTermRect;

typedef struct {
    char name[256];
    CTermRect window_frame;
    double left_sidebar_width;
    double right_sidebar_width;
    bool left_sidebar_visible;
    bool right_sidebar_visible;
    int terminal_split_count;
    double split_ratios[16];
    bool split_horizontal;
    int64_t timestamp;
} CTermLayout;

typedef struct CTermLayoutStore CTermLayoutStore;

CTermLayoutStore* cterm_layout_store_create(const char* storage_path);
void cterm_layout_store_destroy(CTermLayoutStore* store);
bool cterm_layout_save(CTermLayoutStore* store, const CTermLayout* layout);
bool cterm_layout_load(CTermLayoutStore* store, const char* name, CTermLayout* out);
bool cterm_layout_delete(CTermLayoutStore* store, const char* name);
int cterm_layout_list(CTermLayoutStore* store, CTermLayout* out_layouts, int max_count);

// ============================================================
// Token Tracking
// ============================================================

typedef struct {
    char provider[64];
    char model[128];
    int64_t input_tokens;
    int64_t output_tokens;
    int64_t cache_read_tokens;
    int64_t cache_write_tokens;
    double cost_usd;
    int64_t timestamp;
    char session_id[64];
} CTermTokenEntry;

typedef struct {
    int64_t total_input_tokens;
    int64_t total_output_tokens;
    int64_t total_cache_read_tokens;
    int64_t total_cache_write_tokens;
    double total_cost_usd;
    int entry_count;
} CTermTokenSummary;

typedef struct CTermTokenTracker CTermTokenTracker;

CTermTokenTracker* cterm_token_tracker_create(const char* storage_path);
void cterm_token_tracker_destroy(CTermTokenTracker* tracker);
bool cterm_token_record(CTermTokenTracker* tracker, const CTermTokenEntry* entry);
CTermTokenSummary cterm_token_get_session_summary(CTermTokenTracker* tracker, const char* session_id);
CTermTokenSummary cterm_token_get_total_summary(CTermTokenTracker* tracker);
bool cterm_token_save(CTermTokenTracker* tracker);
bool cterm_token_load(CTermTokenTracker* tracker);

// ============================================================
// Project Management
// ============================================================

typedef struct {
    char name[256];
    char path[1024];
    char editor[256];
    char description[512];
    int64_t last_opened;
    bool pinned;
} CTermProject;

typedef struct CTermProjectStore CTermProjectStore;

CTermProjectStore* cterm_project_store_create(const char* storage_path);
void cterm_project_store_destroy(CTermProjectStore* store);
bool cterm_project_add(CTermProjectStore* store, const CTermProject* project);
bool cterm_project_update(CTermProjectStore* store, const CTermProject* project);
bool cterm_project_remove(CTermProjectStore* store, const char* name);
int cterm_project_list(CTermProjectStore* store, CTermProject* out, int max_count);
bool cterm_project_get(CTermProjectStore* store, const char* name, CTermProject* out);

// ============================================================
// Agent Presets
// ============================================================

typedef struct {
    char name[128];
    char command[1024];
    char description[512];
    char provider[64];
    char icon[32];
    char working_dir[1024];
    char keyboard_shortcut[32];
    bool auto_apply;
} CTermAgentPreset;

typedef struct CTermAgentStore CTermAgentStore;

CTermAgentStore* cterm_agent_store_create(const char* storage_path);
void cterm_agent_store_destroy(CTermAgentStore* store);
bool cterm_agent_preset_add(CTermAgentStore* store, const CTermAgentPreset* preset);
bool cterm_agent_preset_update(CTermAgentStore* store, const CTermAgentPreset* preset);
bool cterm_agent_preset_remove(CTermAgentStore* store, const char* name);
int cterm_agent_preset_list(CTermAgentStore* store, CTermAgentPreset* out, int max_count);
bool cterm_agent_preset_get(CTermAgentStore* store, const char* name, CTermAgentPreset* out);

#ifdef __cplusplus
}
#endif

#endif // CTERM_H
