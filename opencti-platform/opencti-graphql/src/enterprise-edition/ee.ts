import type { AuthContext } from '../types/user';
import { getEntityFromCache } from '../database/cache';
import type { BasicStoreSettings } from '../types/settings';
import { SYSTEM_USER } from '../utils/access';
import { ENTITY_TYPE_SETTINGS } from '../schema/internalObject';
import { UnsupportedError } from '../config/errors';

// FORK: EE bypass for local testing — all features unlocked
export const isEnterpriseEdition = async (_context: AuthContext) => {
  return true;
};

export const isEnterpriseEditionFromSettings = (_settings?: Pick<BasicStoreSettings, 'valid_enterprise_edition'>): boolean => {
  return true;
};

export const checkEnterpriseEdition = async (_context: AuthContext) => {
  // no-op: EE always enabled
};
