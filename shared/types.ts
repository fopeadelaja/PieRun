// API types shared by client and server.
// Money and ids are strings on the wire. See CLAUDE.md.

export type Snack = {
  id: string;
  name: string;
  price: string;
};
