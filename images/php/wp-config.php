<?php
/**
 * wp-config for containers: everything comes from the environment, nothing is
 * generated at runtime. Non-secret, cluster-level settings live in
 * wp-config-extra.php (mounted from the php-config ConfigMap).
 */

$env = static function (string $key, ?string $default = null): ?string {
    $v = getenv($key);
    return $v === false || $v === '' ? $default : $v;
};

define('DB_NAME', $env('WORDPRESS_DB_NAME', 'wordpress'));
define('DB_USER', $env('WORDPRESS_DB_USER', 'wordpress'));
define('DB_PASSWORD', $env('WORDPRESS_DB_PASSWORD', ''));
define('DB_HOST', $env('WORDPRESS_DB_HOST', 'mariadb'));
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');
$table_prefix = $env('WORDPRESS_TABLE_PREFIX', 'wp_');

foreach (['AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY', 'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT'] as $k) {
    $v = $env($k);
    if ($v === null) {
        http_response_code(500);
        exit("Missing secret {$k}");
    }
    define($k, $v);
}

if ($env('WP_HOME')) {
    define('WP_HOME', $env('WP_HOME'));
    define('WP_SITEURL', $env('WP_SITEURL', $env('WP_HOME')));
}

define('WP_DEBUG', $env('WP_DEBUG') === 'true');
define('WP_DEBUG_LOG', false);
define('WP_DEBUG_DISPLAY', false);

if (file_exists(__DIR__ . '/wp-config-extra.php')) {
    require __DIR__ . '/wp-config-extra.php';
}

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}
require_once ABSPATH . 'wp-settings.php';
