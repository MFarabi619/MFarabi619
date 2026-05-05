CREATE TRIGGER extract_samples_on_insert
    AFTER INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION extract_samples_from_event();
