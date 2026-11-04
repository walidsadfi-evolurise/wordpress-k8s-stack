<?php
/**
 * Plugin Name: Kubernetes health
 * Description: /wp-json/health/v1/ready checks the database and the object cache so readiness reflects the application, not just PHP-FPM. Also strips the X-Powered-By header.
 * Author: Walid Sadfi
 * Version: 1.0.0
 */

if (!defined('ABSPATH')) {
    exit;
}

header_remove('X-Powered-By');

add_action('rest_api_init', static function (): void {
    register_rest_route('health/v1', '/ready', [
        'methods' => 'GET',
        'permission_callback' => '__return_true',
        'callback' => static function (): WP_REST_Response {
            global $wpdb;
            $checks = [
                'db' => $wpdb->get_var('SELECT 1') === '1',
                'object_cache' => (bool) wp_using_ext_object_cache() && wp_cache_set('k8s_ready_probe', time(), '', 30),
            ];
            $ok = !in_array(false, $checks, true);
            return new WP_REST_Response(['status' => $ok ? 'ok' : 'degraded', 'checks' => $checks], $ok ? 200 : 503);
        },
    ]);
});
