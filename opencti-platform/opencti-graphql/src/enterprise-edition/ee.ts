import type { AuthContext } from '../types/user';
import type { BasicStoreSettings } from '../types/settings';

export const isEnterpriseEdition = async (_context: AuthContext) => true;
export const isEnterpriseEditionFromSettings = (_settings?: Pick<BasicStoreSettings, 'valid_enterprise_edition'>): boolean => true;
export const checkEnterpriseEdition = async (_context: AuthContext) => { return; };
