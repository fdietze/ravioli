export function classes(node, classes) {
  setCustomClasses(node, classes);
  return {
    update(classes) {
      setCustomClasses(node, classes);
    },
  };
}

/**
 * 
 * @param {HTMLElement} node 
 * @param {{[key: string]: string}} classes 
 */
function setCustomClasses(node, classes) {
  Object.entries(classes).forEach(([key, value]) => {
    if (value) {
      node.classList.add(key);
    } else {
      node.classList.remove(key);
    }
  });
  node.classList.add();
}
