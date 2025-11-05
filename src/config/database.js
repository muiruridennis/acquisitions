/**
 * Database configuration for the application.
 *
 * This module initializes the database connection using the Neon database service.
 * It checks the environment and configures the connection settings accordingly.
 *
 * @module database
 * @requires dotenv/config
 * @requires @neondatabase/serverless
 * @requires drizzle-orm/neon-http
 *
 * @constant {Object} sql - The SQL client instance for the Neon database.
 * @constant {Object} db - The Drizzle ORM instance for interacting with the database.
 */
import 'dotenv/config';
import { neon, neonConfig } from '@neondatabase/serverless';
import { drizzle } from 'drizzle-orm/neon-http';

if (process.env.NODE_ENV === 'development') {
  neonConfig.fetchEndpoint = 'http://neon-local:5432/sql';
  neonConfig.useSecureWebSocket = false;
  neonConfig.poolQueryViaFetch = true;
}

const sql = neon(process.env.DATABASE_URL);
const db = drizzle(sql);
export { db, sql };
