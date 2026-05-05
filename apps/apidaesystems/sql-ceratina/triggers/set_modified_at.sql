CREATE TRIGGER set_modified_at BEFORE UPDATE ON assets FOR EACH ROW EXECUTE FUNCTION set_modified_at();
CREATE TRIGGER set_modified_at BEFORE UPDATE ON organizations FOR EACH ROW EXECUTE FUNCTION set_modified_at();
CREATE TRIGGER set_modified_at BEFORE UPDATE ON stacks FOR EACH ROW EXECUTE FUNCTION set_modified_at();
CREATE TRIGGER set_modified_at BEFORE UPDATE ON resources FOR EACH ROW EXECUTE FUNCTION set_modified_at();
CREATE TRIGGER set_modified_at BEFORE UPDATE ON ipv4_addresses FOR EACH ROW EXECUTE FUNCTION set_modified_at();
