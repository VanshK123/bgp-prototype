#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

// Radix trie node structure
typedef struct trie_node {
    struct trie_node *children[2];  // 0 and 1 for binary trie
    char *prefix;
    int prefix_len;
    void *data;  // Route data
    int is_leaf;
} trie_node_t;

// Route entry structure
typedef struct route_entry {
    uint32_t prefix;
    int prefix_len;
    uint32_t next_hop;
    int as_path[10];
    int as_path_len;
    int local_pref;
    int med;
    time_t last_update;
} route_entry_t;

// Create new trie node
trie_node_t* create_trie_node() {
    trie_node_t *node = malloc(sizeof(trie_node_t));
    if (!node) return NULL;
    
    node->children[0] = NULL;
    node->children[1] = NULL;
    node->prefix = NULL;
    node->prefix_len = 0;
    node->data = NULL;
    node->is_leaf = 0;
    
    return node;
}

// Convert IP to binary string
void ip_to_binary(uint32_t ip, int prefix_len, char *binary) {
    for (int i = 0; i < 32; i++) {
        binary[i] = ((ip >> (31 - i)) & 1) ? '1' : '0';
    }
    binary[prefix_len] = '\0';
}

// Insert route into trie
int insert_route(trie_node_t *root, route_entry_t *route) {
    char binary[33];
    ip_to_binary(route->prefix, route->prefix_len, binary);
    
    trie_node_t *current = root;
    
    for (int i = 0; i < route->prefix_len; i++) {
        int bit = binary[i] - '0';
        
        if (!current->children[bit]) {
            current->children[bit] = create_trie_node();
            if (!current->children[bit]) return -1;
        }
        
        current = current->children[bit];
    }
    
    current->data = route;
    current->is_leaf = 1;
    return 0;
}

// Lookup route in trie (optimized)
route_entry_t* lookup_route_optimized(trie_node_t *root, uint32_t ip) {
    trie_node_t *current = root;
    route_entry_t *best_match = NULL;
    
    // Use bitwise operations for faster traversal
    for (int i = 0; i < 32; i++) {
        int bit = (ip >> (31 - i)) & 1;
        
        if (!current->children[bit]) {
            break;
        }
        
        current = current->children[bit];
        
        if (current->is_leaf) {
            best_match = (route_entry_t*)current->data;
        }
    }
    
    return best_match;
}

// Delete route from trie
int delete_route(trie_node_t *root, uint32_t prefix, int prefix_len) {
    char binary[33];
    ip_to_binary(prefix, prefix_len, binary);
    
    trie_node_t *current = root;
    trie_node_t **path[32];
    int path_len = 0;
    
    for (int i = 0; i < prefix_len; i++) {
        int bit = binary[i] - '0';
        
        if (!current->children[bit]) {
            return -1;  // Route not found
        }
        
        path[path_len++] = &current->children[bit];
        current = current->children[bit];
    }
    
    if (!current->is_leaf) {
        return -1;  // Route not found
    }
    
    current->is_leaf = 0;
    current->data = NULL;
    
    // Clean up unnecessary nodes
    for (int i = path_len - 1; i >= 0; i--) {
        trie_node_t *node = *path[i];
        if (!node->is_leaf && !node->children[0] && !node->children[1]) {
            free(node);
            *path[i] = NULL;
        } else {
            break;
        }
    }
    
    return 0;
}

// Performance profiling functions
typedef struct {
    clock_t start_time;
    clock_t end_time;
    int operation_count;
} perf_stats_t;

perf_stats_t* create_perf_stats() {
    perf_stats_t *stats = malloc(sizeof(perf_stats_t));
    stats->start_time = 0;
    stats->end_time = 0;
    stats->operation_count = 0;
    return stats;
}

void start_timing(perf_stats_t *stats) {
    stats->start_time = clock();
}

void end_timing(perf_stats_t *stats) {
    stats->end_time = clock();
    stats->operation_count++;
}

double get_avg_time(perf_stats_t *stats) {
    if (stats->operation_count == 0) return 0.0;
    return ((double)(stats->end_time - stats->start_time)) / 
           (CLOCKS_PER_SEC * stats->operation_count);
}

// Bulk route insertion for performance testing
int bulk_insert_routes(trie_node_t *root, route_entry_t *routes, int count) {
    perf_stats_t *stats = create_perf_stats();
    start_timing(stats);
    
    for (int i = 0; i < count; i++) {
        if (insert_route(root, &routes[i]) != 0) {
            return -1;
        }
    }
    
    end_timing(stats);
    printf("Bulk insert of %d routes completed in %.6f seconds avg\n", 
           count, get_avg_time(stats));
    
    free(stats);
    return 0;
}

// Memory-efficient route lookup with caching
typedef struct {
    uint32_t ip;
    route_entry_t *route;
    time_t timestamp;
} route_cache_entry_t;

typedef struct {
    route_cache_entry_t *entries;
    int size;
    int capacity;
} route_cache_t;

route_cache_t* create_route_cache(int capacity) {
    route_cache_t *cache = malloc(sizeof(route_cache_t));
    cache->entries = malloc(sizeof(route_cache_entry_t) * capacity);
    cache->size = 0;
    cache->capacity = capacity;
    return cache;
}

route_entry_t* lookup_with_cache(trie_node_t *root, route_cache_t *cache, 
                                uint32_t ip, int cache_ttl) {
    time_t now = time(NULL);
    
    // Check cache first
    for (int i = 0; i < cache->size; i++) {
        if (cache->entries[i].ip == ip && 
            (now - cache->entries[i].timestamp) < cache_ttl) {
            return cache->entries[i].route;
        }
    }
    
    // Lookup in trie
    route_entry_t *route = lookup_route_optimized(root, ip);
    
    // Add to cache
    if (route && cache->size < cache->capacity) {
        cache->entries[cache->size].ip = ip;
        cache->entries[cache->size].route = route;
        cache->entries[cache->size].timestamp = now;
        cache->size++;
    }
    
    return route;
}

// Cleanup functions
void free_trie_node(trie_node_t *node) {
    if (!node) return;
    
    free_trie_node(node->children[0]);
    free_trie_node(node->children[1]);
    
    if (node->data) {
        free(node->data);
    }
    
    free(node);
}

void free_route_cache(route_cache_t *cache) {
    if (cache) {
        free(cache->entries);
        free(cache);
    }
} 