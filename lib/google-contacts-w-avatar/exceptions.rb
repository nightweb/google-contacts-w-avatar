module GoogleContacts
  class Unauthorized < RuntimeError; end
  class InvalidKind < RuntimeError; end
  class InvalidRequest < RuntimeError; end
  class RecordNotFound < RuntimeError; end
  class InvalidResponse < RuntimeError; end
end